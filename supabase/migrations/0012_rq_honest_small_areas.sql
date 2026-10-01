-- Roofing Quote Generator :: stop inflating small roof areas
--
-- The engine clamped any roof area under 200 sq ft up to 200 sq ft:
--
--   if v_area > 0 and v_area < 200 then
--     v_area := 200;
--   end if;
--
-- That was meant to make tiny jobs meet the contractor minimum, but it did the
-- opposite: it multiplied every per-sqft line by up to 4x while still reporting
-- area_source as "Customer supplied measured area". A 50 sq ft shed priced as a
-- 200 sq ft roof came to $111,571.97, and because the inflated subtotal was
-- already far above min_charge, the minimum charge never engaged either
-- (min_charge_adjustment stayed 0).
--
-- The clamp is removed. Line quantities now reflect the area the customer
-- actually gave us, and the existing flat min_charge floor in the totals block
-- is what lifts a genuinely too-small job. The warning is kept, reworded to
-- describe what actually happens.
--
-- This replaces rq_compute_quote in full; no money math changes other than
-- quantities no longer being scaled up.

create or replace function public.rq_compute_quote(p_contractor_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c public.rq_contractors;
  v_a jsonb := coalesce(p_answers, '{}'::jsonb);

  -- geometry and access
  v_area numeric := 0;
  v_area_source text := '';
  v_footprint numeric;
  v_stories numeric;
  v_pitch numeric;
  v_slope_mult numeric;
  v_story_mult numeric;
  v_access_mult numeric;
  v_labor_mult numeric;
  v_layers numeric;
  v_tearoff_mult numeric;
  v_waste numeric;
  v_deck_pct numeric;

  -- selections
  v_project text;
  v_system text;
  v_decking text;
  v_underlayment text;
  v_ventilation text;
  v_haul_away text;
  v_gutter_service text;
  v_ice_pct numeric;

  -- counts
  v_valleys numeric;
  v_skylights numeric;
  v_chimneys numeric;
  v_gutter_lf numeric;
  v_gutter_new_qty numeric;
  v_gutter_remove_qty numeric;
  v_bins numeric;
  v_permits numeric;
  v_tarps numeric;

  -- line item machine
  v_steps jsonb;
  v_step jsonb;
  v_rate jsonb;
  v_items jsonb := '[]'::jsonb;
  v_warnings jsonb := '[]'::jsonb;

  v_qty numeric;
  v_price numeric;
  v_unit text;
  v_disposal_qty numeric;
  v_descr_teardown text;
  v_descr_gutter_new text;
  v_descr_gutter_remove text;

  v_subtotal numeric := 0;
  v_contingency numeric := 0;
  v_overhead numeric := 0;
  v_profit numeric := 0;
  v_tax numeric := 0;
  v_min_adjust numeric := 0;
  v_total numeric := 0;
  v_deposit numeric := 0;
  v_price_per_sqft numeric := 0;
begin
  select * into v_c from public.rq_contractors where id = p_contractor_id;
  if not found then
    raise exception 'Contractor not found' using errcode = 'no_data_found';
  end if;

  -- ---- selections -------------------------------------------------------
  v_project := lower(coalesce(public.rq_txt(v_a, 'project_type', 'replacement'), 'replacement'));
  v_system := lower(coalesce(public.rq_txt(v_a, 'roof_system', 'arch'), 'arch'));
  v_decking := lower(coalesce(public.rq_txt(v_a, 'decking_condition', 'good'), 'good'));
  v_underlayment := lower(coalesce(public.rq_txt(v_a, 'underlayment', 'synthetic'), 'synthetic'));
  v_ventilation := lower(coalesce(public.rq_txt(v_a, 'ventilation', 'soffit_ridge'), 'soffit_ridge'));
  v_haul_away := lower(coalesce(public.rq_txt(v_a, 'haul_away', 'dumpster'), 'dumpster'));
  v_gutter_service := lower(coalesce(public.rq_txt(v_a, 'gutter_service', 'new'), 'new'));

  v_stories := greatest(public.rq_num(v_a, 'stories', 1), 1);
  v_pitch := public.rq_num(v_a, 'pitch', 6);
  v_layers := public.rq_num(v_a, 'existing_layers', 1);
  v_valleys := public.rq_num(v_a, 'valleys', 0);
  v_skylights := public.rq_num(v_a, 'skylights', 0);
  v_chimneys := public.rq_num(v_a, 'chimneys', 0);
  v_waste := v_c.waste_factor_pct / 100;

  -- ---- area -------------------------------------------------------------
  v_area := public.rq_num(v_a, 'roof_area_sqft', 0);
  if v_area > 0 then
    v_area_source := 'Customer supplied measured area';
  else
    v_footprint := public.rq_num(v_a, 'footprint_sqft', 0);
    if v_footprint > 0 then
      -- 1.12 covers overhangs and the smaller secondary slopes of a typical
      -- footprint; this is the same rule of thumb estimators use verbally.
      v_area := round(v_footprint * v_stories * 1.12, 0);
      v_area_source := 'Estimated from footprint x stories x 1.12';
    else
      v_area := 0;
      v_area_source := 'Not provided';
    end if;
  end if;
  -- The area is used exactly as given. A small job is not made bigger to reach
  -- the minimum; the flat min_charge in the totals block does that instead, so
  -- the quantities on this quote stay true to the roof.
  if v_area > 0 and v_area < 200 then
    v_warnings := public.rq_add_warning(
      v_warnings,
      'At ' || round(v_area, 0)::text || ' sq ft this is a small job, so the contractor minimum job charge is likely to apply.'
    );
  end if;

  -- ---- labor multipliers -------------------------------------------------
  v_slope_mult := case
    when v_pitch <= 2 then 1.10
    when v_pitch <= 4 then 1.00
    when v_pitch <= 6 then 1.10
    when v_pitch <= 8 then 1.20
    when v_pitch <= 10 then 1.32
    when v_pitch <= 12 then 1.45
    else 1.60
  end;
  v_story_mult := case
    when v_stories <= 1 then 1.00
    when v_stories <= 2 then 1.15
    when v_stories <= 3 then 1.30
    else 1.45
  end;
  v_access_mult := case lower(coalesce(public.rq_txt(v_a, 'access_difficulty', 'moderate'), 'moderate'))
    when 'easy' then 1.00
    when 'difficult' then 1.28
    else 1.12
  end;
  v_labor_mult := round(v_slope_mult * v_story_mult * v_access_mult, 3);

  -- Extra layers get progressively harder to pull, not just more numerous.
  if v_project = 'replacement' and v_layers >= 1 then
    v_tearoff_mult := 1 + 0.35 * (v_layers - 1);
  else
    v_tearoff_mult := 0;
  end if;

  v_deck_pct := case v_decking
    when 'fair' then 5
    when 'poor' then 18
    when 'rotted' then 100
    else 0
  end;

  v_ice_pct := public.rq_num(v_a, 'ice_shield_coverage', 0);
  if public.rq_bool(v_a, 'ice_water_shield', false) and v_ice_pct = 0 then
    v_ice_pct := 25;
  end if;

  v_bins := case when v_haul_away = 'dumpster' and v_tearoff_mult > 0 then 1 else 0 end;
  v_permits := case when public.rq_bool(v_a, 'permit_needed', true) then 1 else 0 end;
  v_tarps := case when public.rq_bool(v_a, 'protection_needed', false) then 1 else 0 end;

  v_disposal_qty := case when v_tearoff_mult > 0 then v_area else 0 end;
  v_descr_teardown := case
    when v_tearoff_mult > 0 then 'Removal of ' || v_layers::text || ' existing layer(s)'
    else 'No removal required'
  end;

  -- ---- gutters ----------------------------------------------------------
  -- A length on its own is ambiguous, so it never implies removal work. Each
  -- line is only priced when the customer asked for that specific service.
  v_gutter_lf := public.rq_num(v_a, 'gutter_linear_ft', 0);
  case v_gutter_service
    when 'none' then
      v_gutter_new_qty := 0;
      v_gutter_remove_qty := 0;
      v_gutter_lf := 0;
    when 'replace' then
      v_gutter_new_qty := v_gutter_lf;
      v_gutter_remove_qty := v_gutter_lf;
    when 'remove' then
      v_gutter_new_qty := 0;
      v_gutter_remove_qty := v_gutter_lf;
    else
      v_gutter_new_qty := v_gutter_lf;
      v_gutter_remove_qty := 0;
  end case;

  v_descr_gutter_new := case
    when v_gutter_service = 'replace'
      then 'Replacement gutter and downspout, ' || v_gutter_lf::text || ' linear ft'
    else 'New gutter and downspout, ' || v_gutter_lf::text || ' linear ft'
  end;
  v_descr_gutter_remove := case
    when v_gutter_service = 'replace'
      then 'Removal and haul-away of the existing gutter, ' || v_gutter_lf::text || ' linear ft'
    else 'Existing gutter removal and haul-away, ' || v_gutter_lf::text || ' linear ft'
  end;

  -- ---- warnings the prose generator must see ----------------------------
  if v_area = 0 then
    v_warnings := public.rq_add_warning(v_warnings, 'No roof area was supplied; this price is a placeholder and must be re-run after an on-site measurement.');
  else
    v_warnings := public.rq_add_warning(v_warnings, v_area_source || ' (' || round(v_area, 0)::text || ' sq ft). The price is only as accurate as that area.');
  end if;
  if v_deck_pct >= 18 then
    v_warnings := public.rq_add_warning(v_warnings, 'Decking is described as ' || v_decking || '. Hidden rot can push this job well past the quoted total once the deck is opened.');
  elsif v_deck_pct > 0 then
    v_warnings := public.rq_add_warning(v_warnings, 'Some decking repair is allowed for; verify on site before the crew starts.');
  end if;
  if v_ventilation = 'none' then
    v_warnings := public.rq_add_warning(v_warnings, 'The attic has no planned ventilation changes. On an older home this shortens shingle life and can void manufacturer warranties.');
  end if;
  if v_pitch >= 10 then
    v_warnings := public.rq_add_warning(v_warnings, 'A pitch of ' || v_pitch::text || ' in 12 needs dedicated fall protection and slows the crew down.');
  end if;
  if v_pitch <= 2 and v_system = 'arch' then
    v_warnings := public.rq_add_warning(v_warnings, 'Asphalt shingles are not warrantied below a 2 in 12 pitch. A low-slope membrane system should be quoted instead.');
  end if;
  if v_stories >= 3 then
    v_warnings := public.rq_add_warning(v_warnings, 'Three or more storeys: material handling and access dominate the cost of this job.');
  end if;
  if v_layers >= 3 then
    v_warnings := public.rq_add_warning(v_warnings, v_layers::text || ' existing layers is a very heavy tear-off and usually signals deferred maintenance.');
  end if;
  if v_skylights > 0 or v_chimneys > 0 then
    v_warnings := public.rq_add_warning(v_warnings, 'Penetrations (' || v_skylights::text || ' skylight(s), ' || v_chimneys::text || ' chimney(s)) are where most roof leaks actually start and are usually the weakest point of the new roof.');
  end if;
  if v_gutter_service = 'remove' then
    v_warnings := public.rq_add_warning(v_warnings, 'Gutter removal is priced without a replacement. Confirm with the customer whether water needs redirecting before the crew leaves.');
  end if;
  if v_project = 'overlay' then
    v_warnings := public.rq_add_warning(v_warnings, 'This is an overlay over an existing roof. It is cheaper but caps the roof at the life of the layer underneath; existing leaks are not addressed.');
  end if;
  if v_system in ('metal', 'tile', 'wood_shake') then
    v_warnings := public.rq_add_warning(v_warnings, 'A ' || v_system || ' roof is specialist work with long lead times for material. The schedule should assume a delivery delay of several weeks.');
  end if;
  if v_system = 'metal' and v_pitch < 4 then
    v_warnings := public.rq_add_warning(v_warnings, 'Metal panels at a ' || v_pitch::text || ' in 12 pitch will pond water and corrode. Mechanical roof fasteners are required below 6 in 12.');
  end if;

  -- ---- line items -------------------------------------------------------
  -- Every case-derived value is resolved into a variable above, so this
  -- builder only ever passes plain expressions to jsonb_build_object.
  v_steps := jsonb_build_array(
    jsonb_build_object(
      'code', 'material_' || v_system,
      'qty', round(v_area * (1 + v_waste), 2),
      'mult', 1.0,
      'descr', 'Roof area including ' || trim(trailing '.' from v_c.waste_factor_pct::text) || '% waste allowance'
    ),
    jsonb_build_object(
      'code', 'labor_install',
      'qty', v_area,
      'mult', v_labor_mult,
      'descr', 'Tear-off, deck prep, dry-in and install at ' || v_pitch::text || ' in 12 pitch'
    ),
    jsonb_build_object(
      'code', 'teardown_per_layer',
      'qty', v_area,
      'mult', v_tearoff_mult,
      'descr', v_descr_teardown
    ),
    jsonb_build_object(
      'code', 'underlayment_' || v_underlayment,
      'qty', v_area,
      'mult', 1.0,
      'descr', 'New underlayment across the full roof area'
    ),
    jsonb_build_object(
      'code', 'ice_water_shield',
      'qty', round(v_area * v_ice_pct / 100, 2),
      'mult', 1.0,
      'descr', 'Self-adhered ice and water shield over eaves and valleys'
    ),
    jsonb_build_object(
      'code', 'ventilation_' || v_ventilation,
      'qty', v_area,
      'mult', 1.0,
      'descr', 'Attic ventilation intake and exhaust'
    ),
    jsonb_build_object(
      'code', 'flashing_valley',
      'qty', v_valleys * 60,
      'mult', 1.0,
      'descr', 'Woven or metal valleys, 60 linear ft allowance each'
    ),
    jsonb_build_object(
      'code', 'skylight_kit',
      'qty', v_skylights,
      'mult', 1.0,
      'descr', 'Skylight curb flashing kit'
    ),
    jsonb_build_object(
      'code', 'chimney_flashing',
      'qty', v_chimneys,
      'mult', 1.0,
      'descr', 'Chimney step flashing and cricket'
    ),
    jsonb_build_object(
      'code', 'gutter_new',
      'qty', v_gutter_new_qty,
      'mult', 1.0,
      'descr', v_descr_gutter_new
    ),
    jsonb_build_object(
      'code', 'gutter_remove',
      'qty', v_gutter_remove_qty,
      'mult', 1.0,
      'descr', v_descr_gutter_remove
    ),
    jsonb_build_object(
      'code', 'decking_repair',
      'qty', round(v_area * v_deck_pct / 100, 2),
      'mult', 1.0,
      'descr', 'Plywood sheathing replacement, ' || v_deck_pct::text || '% of area'
    ),
    jsonb_build_object(
      'code', 'disposal_dump',
      'qty', v_disposal_qty,
      'mult', 1.0,
      'descr', 'Debris collection and haul-away'
    ),
    jsonb_build_object(
      'code', 'disposal_haulaway_bin',
      'qty', v_bins,
      'mult', 1.0,
      'descr', 'Dumpster drop-off and final sweep'
    ),
    jsonb_build_object(
      'code', 'permit',
      'qty', v_permits,
      'mult', 1.0,
      'descr', 'Building permit, plan check and final inspection'
    ),
    jsonb_build_object(
      'code', 'protection_tarps',
      'qty', v_tarps,
      'mult', 1.0,
      'descr', 'Property protection, plywood covers and site cleanup'
    )
  );

  for v_step in
    select e.value
    from jsonb_array_elements(v_steps) as e(value)
  loop
    v_rate := public.rq_rate_lookup(p_contractor_id, v_step ->> 'code');
    if v_rate is null then
      -- The contractor has not priced this line, so it is left off the quote
      -- entirely rather than silently quoted at zero.
      v_warnings := public.rq_add_warning(
        v_warnings,
        'Rate card has no price for "' || (v_step ->> 'code') || '", so that line was left off this quote.'
      );
      continue;
    end if;

    v_qty := (v_step ->> 'qty')::numeric;
    v_price := (v_rate ->> 'unit_price')::numeric * (v_step ->> 'mult')::numeric;
    v_unit := v_rate ->> 'unit';
    if v_unit = 'square' then
      v_qty := round(v_qty / 100, 2);
    end if;

    v_items := public.rq_add_item(
      v_items,
      coalesce(v_rate ->> 'category', 'accessory'),
      v_step ->> 'code',
      v_rate ->> 'label',
      v_step ->> 'descr',
      v_qty,
      v_unit,
      v_price
    );
  end loop;

  -- ---- totals -----------------------------------------------------------
  select coalesce(sum((e ->> 'line_total')::numeric), 0)
    into v_subtotal
  from jsonb_array_elements(v_items) e;

  v_contingency := round(v_subtotal * v_c.contingency_pct / 100, 2);
  v_overhead := round((v_subtotal + v_contingency) * v_c.overhead_pct / 100, 2);
  v_profit := round((v_subtotal + v_contingency + v_overhead) * v_c.profit_pct / 100, 2);
  v_tax := round((v_subtotal + v_contingency + v_overhead + v_profit) * v_c.tax_pct / 100, 2);

  v_total := round(v_subtotal + v_contingency + v_overhead + v_profit + v_tax, 2);
  if v_total < v_c.min_charge then
    v_min_adjust := round(v_c.min_charge - v_total, 2);
    v_total := v_c.min_charge;
    v_warnings := public.rq_add_warning(v_warnings, 'Raised to the contractor minimum job charge.');
  end if;

  v_deposit := round(v_total * v_c.deposit_pct / 100, 2);

  if v_area > 0 then
    v_price_per_sqft := round(v_total / v_area, 2);
  else
    v_price_per_sqft := 0;
  end if;

  -- ---- result -----------------------------------------------------------
  return jsonb_build_object(
    'inputs', jsonb_build_object(
      'project_type', v_project,
      'roof_system', v_system,
      'roof_area_sqft', round(v_area, 2),
      'area_source', v_area_source,
      'stories', v_stories,
      'pitch', v_pitch,
      'existing_layers', v_layers,
      'decking_condition', v_decking,
      'decking_repair_pct', v_deck_pct,
      'access_difficulty', public.rq_txt(v_a, 'access_difficulty', 'moderate'),
      'underlayment', v_underlayment,
      'ventilation', v_ventilation,
      'ice_water_shield', v_ice_pct > 0,
      'ice_shield_coverage_pct', v_ice_pct,
      'valleys', v_valleys,
      'skylights', v_skylights,
      'chimneys', v_chimneys,
      'gutter_service', v_gutter_service,
      'gutter_linear_ft', v_gutter_lf,
      'haul_away', v_haul_away,
      'slope_multiplier', v_slope_mult,
      'story_multiplier', v_story_mult,
      'access_multiplier', v_access_mult,
      'labor_multiplier', v_labor_mult,
      'tearoff_multiplier', round(v_tearoff_mult, 3)
    ),
    'items', v_items,
    'warnings', v_warnings,
    'totals', jsonb_build_object(
      'subtotal', v_subtotal,
      'contingency_total', v_contingency,
      'overhead_total', v_overhead,
      'profit_total', v_profit,
      'tax_total', v_tax,
      'min_charge_adjustment', v_min_adjust,
      'total', v_total,
      'deposit_amount', v_deposit,
      'price_per_sqft', v_price_per_sqft
    ),
    'pricing', jsonb_build_object(
      'waste_factor_pct', v_c.waste_factor_pct,
      'overhead_pct', v_c.overhead_pct,
      'profit_pct', v_c.profit_pct,
      'contingency_pct', v_c.contingency_pct,
      'tax_pct', v_c.tax_pct,
      'min_charge', v_c.min_charge,
      'deposit_pct', v_c.deposit_pct,
      'valid_days', v_c.valid_days,
      'warranty_years', v_c.warranty_years,
      'currency', v_c.currency
    )
  );
end;
$$;
