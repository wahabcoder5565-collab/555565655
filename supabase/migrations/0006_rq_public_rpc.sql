-- Roofing Quote Generator :: internals shared by the public and staff flows

-- Contractor row for the signed-in user, created on demand. The first
-- contractor to sign up becomes the primary, which is where the public
-- wizard sends new quote requests.
create or replace function public.rq_ensure_contractor()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select c.id into v_id
  from public.rq_contractors c
  where c.owner_id = auth.uid()
  limit 1;

  if v_id is null then
    insert into public.rq_contractors (
      owner_id, company_name, contact_email, is_primary
    )
    values (
      auth.uid(),
      coalesce(auth.jwt() ->> 'user_metadata' ->> 'company_name', ''),
      lower(coalesce(auth.jwt() ->> 'email', '')),
      not exists (select 1 from public.rq_contractors)
    )
    on conflict (owner_id) do nothing
    returning id into v_id;

    if v_id is null then
      select c.id into v_id
      from public.rq_contractors c
      where c.owner_id = auth.uid()
      limit 1;
    end if;
  end if;

  return v_id;
end;
$$;

-- Contractor overrides win over the shared system template, matched by key.
create or replace function public.rq_effective_questions(p_contractor_id uuid)
returns setof public.rq_questions
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (q.key) q.*
  from public.rq_questions q
  where q.contractor_id is null or q.contractor_id = p_contractor_id
  order by q.key, q.contractor_id nulls last, q.is_active desc, q.sort_order;
$$;

create or replace function public.rq_effective_rate_items(p_contractor_id uuid)
returns setof public.rq_rate_items
language sql
stable
security definer
set search_path = ''
as $$
  select distinct on (ri.code) ri.*
  from public.rq_rate_items ri
  where ri.contractor_id is null or ri.contractor_id = p_contractor_id
  order by ri.code, ri.contractor_id nulls last, ri.is_active desc, ri.sort_order;
$$;

-- Values arriving from a form are coerced to the type the question declares
-- and any key the contractor does not define is dropped. Nothing a customer
-- types ever reaches the pricing engine under a key we did not author.
create or replace function public.rq_coerce_answers(p_contractor_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
immutable
security definer
set search_path = ''
as $$
declare
  v_out jsonb := '{}'::jsonb;
  v_entry record;
  v_type text;
begin
  if p_answers is null then
    return v_out;
  end if;

  for v_entry in
    select e.key, e.value
    from jsonb_each(p_answers) as e(key, value)
  loop
    select q.input_type into v_type
    from public.rq_questions q
    where q.key = v_entry.key
      and (q.contractor_id is null or q.contractor_id = p_contractor_id)
    order by q.contractor_id nulls last
    limit 1;

    if v_type is null then
      continue;
    end if;
    if v_entry.value = 'null'::jsonb then
      continue;
    end if;

    if v_type = 'number' then
      v_out := v_out || jsonb_build_object(
        v_entry.key, public.rq_num(jsonb_build_object('v', v_entry.value), 'v', null)
      );
    elsif v_type = 'boolean' then
      v_out := v_out || jsonb_build_object(
        v_entry.key, public.rq_bool(jsonb_build_object('v', v_entry.value), 'v', false)
      );
    else
      v_out := v_out || jsonb_build_object(
        v_entry.key, public.rq_txt(jsonb_build_object('v', v_entry.value), 'v', '')
      );
    end if;
  end loop;

  return v_out;
end;
$$;

-- Applies the contractor's markup ladder to a set of line items. Shared by the
-- pricing engine's output and by manual line item edits in the dashboard, so
-- an edited quote and a generated quote are always marked up identically.
create or replace function public.rq_apply_totals(
  p_items jsonb,
  p_pricing jsonb,
  p_area numeric
)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_subtotal numeric := 0;
  v_contingency numeric;
  v_overhead numeric;
  v_profit numeric;
  v_tax numeric;
  v_min_adjust numeric := 0;
  v_total numeric;
  v_base numeric;
begin
  select coalesce(sum(coalesce((e ->> 'line_total')::numeric, 0)), 0)
    into v_subtotal
  from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) e;

  v_contingency := round(v_subtotal * public.rq_num(p_pricing, 'contingency_pct', 0) / 100, 2);
  v_base := v_subtotal + v_contingency;
  v_overhead := round(v_base * public.rq_num(p_pricing, 'overhead_pct', 0) / 100, 2);
  v_base := v_base + v_overhead;
  v_profit := round(v_base * public.rq_num(p_pricing, 'profit_pct', 0) / 100, 2);
  v_base := v_base + v_profit;
  v_tax := round(v_base * public.rq_num(p_pricing, 'tax_pct', 0) / 100, 2);

  v_total := round(v_base + v_tax, 2);
  if v_total < public.rq_num(p_pricing, 'min_charge', 0) then
    v_min_adjust := round(public.rq_num(p_pricing, 'min_charge', 0) - v_total, 2);
    v_total := public.rq_num(p_pricing, 'min_charge', 0);
  end if;

  return jsonb_build_object(
    'subtotal', v_subtotal,
    'contingency_total', v_contingency,
    'overhead_total', v_overhead,
    'profit_total', v_profit,
    'tax_total', v_tax,
    'min_charge_adjustment', v_min_adjust,
    'total', v_total,
    'deposit_amount', round(v_total * public.rq_num(p_pricing, 'deposit_pct', 0) / 100, 2),
    'price_per_sqft', case
      when coalesce(p_area, 0) > 0 then round(v_total / p_area, 2)
      else 0
    end
  );
end;
$$;

-- Creates the quote rows for a lead. Used by the customer submit flow and by
-- the dashboard's re-price action.
create or replace function public.rq_create_quote(p_lead_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_lead public.rq_leads;
  v_computed jsonb;
  v_quote_id uuid;
  v_token text;
  v_number text;
  v_item jsonb;
  v_sort int := 0;
  v_totals jsonb;
begin
  select * into v_lead from public.rq_leads where id = p_lead_id;
  if not found then
    raise exception 'Lead not found' using errcode = 'no_data_found';
  end if;

  v_computed := public.rq_compute_quote(v_lead.contractor_id, v_lead.answers);
  v_totals := v_computed -> 'totals';
  v_token := public.rq_new_token();
  v_number := 'RQ-' || to_char(now(), 'YY') || '-' ||
    lpad(nextval('public.rq_quote_number_seq')::text, 5, '0');

  insert into public.rq_quotes (
    public_token, quote_number, lead_id, contractor_id, status,
    project_type, roof_area_sqft, inputs, answers, pricing,
    subtotal, contingency_total, overhead_total, profit_total, tax_total,
    min_charge_adjustment, total, deposit_amount, price_per_sqft,
    warnings, valid_until, ai_status, ai_engine
  )
  values (
    v_token, v_number, v_lead.id, v_lead.contractor_id, 'sent',
    public.rq_txt(v_lead.answers, 'project_type', 'replacement'),
    (v_computed #> '{inputs,roof_area_sqft}')::numeric,
    v_computed -> 'inputs',
    v_lead.answers,
    v_computed -> 'pricing',
    (v_totals ->> 'subtotal')::numeric,
    (v_totals ->> 'contingency_total')::numeric,
    (v_totals ->> 'overhead_total')::numeric,
    (v_totals ->> 'profit_total')::numeric,
    (v_totals ->> 'tax_total')::numeric,
    (v_totals ->> 'min_charge_adjustment')::numeric,
    (v_totals ->> 'total')::numeric,
    (v_totals ->> 'deposit_amount')::numeric,
    (v_totals ->> 'price_per_sqft')::numeric,
    v_computed -> 'warnings',
    (current_date + make_interval(days => public.rq_num(v_computed -> 'pricing', 'valid_days', 30)::int))::date,
    'pending',
    'rules'
  )
  returning id into v_quote_id;

  for v_item in
    select e.value from jsonb_array_elements(v_computed -> 'items') e
  loop
    insert into public.rq_quote_items (
      quote_id, category, code, label, description,
      quantity, unit, unit_price, line_total, sort_order
    )
    values (
      v_quote_id,
      coalesce(v_item ->> 'category', 'accessory'),
      coalesce(v_item ->> 'code', ''),
      coalesce(v_item ->> 'label', 'Line item'),
      coalesce(v_item ->> 'description', ''),
      coalesce((v_item ->> 'quantity')::numeric, 0),
      coalesce(v_item ->> 'unit', 'sqft'),
      coalesce((v_item ->> 'unit_price')::numeric, 0),
      coalesce((v_item ->> 'line_total')::numeric, 0),
      v_sort
    );
    v_sort := v_sort + 10;
  end loop;

  insert into public.rq_quote_events (quote_id, lead_id, actor_role, action, detail)
  values (v_quote_id, v_lead.id, 'customer', 'quote_generated',
    'Auto-generated from ' || jsonb_array_length(coalesce(v_computed -> 'items', '[]'::jsonb))::text
    || ' priced line items');

  update public.rq_leads
  set status = 'quoted', submitted_at = coalesce(submitted_at, now())
  where id = v_lead.id;

  return jsonb_build_object('quote_id', v_quote_id, 'public_token', v_token, 'quote_number', v_number);
end;
$$;

revoke all on function public.rq_ensure_contractor() from public;
revoke all on function public.rq_effective_questions(uuid) from public;
revoke all on function public.rq_effective_rate_items(uuid) from public;
revoke all on function public.rq_coerce_answers(uuid, jsonb) from public;
revoke all on function public.rq_apply_totals(jsonb, jsonb, numeric) from public;
revoke all on function public.rq_create_quote(uuid) from public;

grant execute on function public.rq_apply_totals(jsonb, jsonb, numeric) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Public flow. Token in, quote out. Nothing here trusts anything except the
-- 192-bit public token, which the customer has been holding all along.
-- ---------------------------------------------------------------------------

create or replace function public.rq_public_config()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_c public.rq_contractors;
begin
  select * into v_c from public.rq_contractors where id = public.rq_default_contractor_id();
  if not found then
    return jsonb_build_object('contractor', null, 'questions', '[]'::jsonb);
  end if;

  return jsonb_build_object(
    'contractor', jsonb_build_object(
      'company_name', v_c.company_name,
      'phone', v_c.phone,
      'website', v_c.website,
      'license_no', v_c.license_no,
      'city', v_c.city,
      'state', v_c.state,
      'brand_color', v_c.brand_color,
      'warranty_years', v_c.warranty_years,
      'currency', v_c.currency
    ),
    'questions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'key', q.key,
        'section', q.section,
        'label', q.label,
        'help_text', q.help_text,
        'input_type', q.input_type,
        'unit', q.unit,
        'options', q.options,
        'required', q.required,
        'min_value', q.min_value,
        'max_value', q.max_value,
        'step_value', q.step_value,
        'sort_order', q.sort_order
      ) order by q.section, q.sort_order)
      from public.rq_effective_questions(v_c.id) q
      where q.is_active
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rq_public_start_lead(
  p_source text default '',
  p_campaign text default ''
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_default_contractor_id();
  v_token text;
begin
  if v_cid is null then
    raise exception 'No contractor is set up yet' using errcode = 'no_data_found';
  end if;

  loop
    v_token := public.rq_new_token();
    exit when not exists (select 1 from public.rq_leads where public_token = v_token);
  end loop;

  insert into public.rq_leads (public_token, contractor_id, utm_source, utm_campaign)
  values (v_token, v_cid, left(coalesce(p_source, ''), 100), left(coalesce(p_campaign, ''), 100));

  return jsonb_build_object('token', v_token);
end;
$$;

create or replace function public.rq_public_lead(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_lead public.rq_leads;
  v_c public.rq_contractors;
begin
  select * into v_lead from public.rq_leads where public_token = p_token;
  if not found then
    raise exception 'Session not found' using errcode = 'no_data_found';
  end if;
  select * into v_c from public.rq_contractors where id = v_lead.contractor_id;

  return jsonb_build_object(
    'token', v_lead.public_token,
    'status', v_lead.status,
    'answers', v_lead.answers,
    'contact', jsonb_build_object(
      'contact_name', v_lead.contact_name,
      'contact_email', v_lead.contact_email,
      'contact_phone', v_lead.contact_phone
    ),
    'current_step', v_lead.current_step,
    'completion', v_lead.completion,
    'contractor', jsonb_build_object(
      'company_name', v_c.company_name,
      'brand_color', v_c.brand_color
    )
  );
end;
$$;

create or replace function public.rq_public_save(
  p_token text,
  p_answers jsonb,
  p_step integer default 0,
  p_contact jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lead public.rq_leads;
  v_answers jsonb;
  v_active int;
  v_answered int;
  v_completion smallint;
begin
  select * into v_lead from public.rq_leads where public_token = p_token;
  if not found then
    raise exception 'Session not found' using errcode = 'no_data_found';
  end if;
  if v_lead.status <> 'draft' then
    raise exception 'This quote request has already been submitted' using errcode = '55000';
  end if;

  v_answers := public.rq_coerce_answers(
    v_lead.contractor_id,
    coalesce(v_lead.answers, '{}'::jsonb) || coalesce(p_answers, '{}'::jsonb)
  );

  select count(*) into v_active
  from public.rq_effective_questions(v_lead.contractor_id) q
  where q.is_active;

  -- A key that was never answered comes back as SQL NULL; a blank text answer
  -- is normalised to JSON null by rq_coerce_answers. Those are the two cases
  -- that count as unanswered.
  select count(*) into v_answered
  from public.rq_effective_questions(v_lead.contractor_id) q
  where q.is_active
    and jsonb_typeof(v_answers -> q.key) is not null
    and v_answers -> q.key <> 'null'::jsonb;

  v_completion := case
    when v_active > 0 then least(round(v_answered * 100.0 / v_active), 100)::smallint
    else 0
  end;

  update public.rq_leads
  set answers = v_answers,
      current_step = greatest(coalesce(p_step, 0), 0),
      completion = v_completion,
      contact_name = case when p_contact ? 'name' then left(coalesce(public.rq_txt(p_contact, 'name', ''), ''), 120) else contact_name end,
      contact_email = case when p_contact ? 'email' then lower(left(coalesce(public.rq_txt(p_contact, 'email', ''), ''), 200)) else contact_email end,
      contact_phone = case when p_contact ? 'phone' then left(coalesce(public.rq_txt(p_contact, 'phone', ''), ''), 40) else contact_phone end,
      property_address = case when jsonb_typeof(v_answers -> 'property_address') is not null then public.rq_txt(v_answers, 'property_address', '') else property_address end,
      property_city = case when jsonb_typeof(v_answers -> 'property_city') is not null then public.rq_txt(v_answers, 'property_city', '') else property_city end,
      property_state = case when jsonb_typeof(v_answers -> 'property_state') is not null then public.rq_txt(v_answers, 'property_state', '') else property_state end,
      property_zip = case when jsonb_typeof(v_answers -> 'property_zip') is not null then public.rq_txt(v_answers, 'property_zip', '') else property_zip end,
      project_type = coalesce(public.rq_txt(v_answers, 'project_type', project_type), project_type)
  where id = v_lead.id;

  return jsonb_build_object(
    'ok', true,
    'completion', v_completion,
    'answered', v_answered,
    'active_questions', v_active
  );
end;
$$;

create or replace function public.rq_public_submit(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_lead public.rq_leads;
  v_missing text[];
  v_quote jsonb;
begin
  select * into v_lead from public.rq_leads where public_token = p_token;
  if not found then
    raise exception 'Session not found' using errcode = 'no_data_found';
  end if;

  select coalesce(array_agg(q.key order by q.sort_order), '{}')
    into v_missing
  from public.rq_effective_questions(v_lead.contractor_id) q
  where q.is_active
    and q.required
    and (
      jsonb_typeof(v_lead.answers -> q.key) is null
      or v_lead.answers -> q.key = 'null'::jsonb
    );

  if array_length(v_missing, 1) is not null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Please answer the required questions before submitting.',
      'missing', to_jsonb(v_missing)
    );
  end if;

  if coalesce(btrim(v_lead.contact_name), '') = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'Please give us a name to put the quote under.',
      'missing', '["contact_name"]'::jsonb
    );
  end if;
  if coalesce(btrim(v_lead.contact_email), '') = '' then
    return jsonb_build_object(
      'ok', false,
      'error', 'Please give us an email address to send the quote to.',
      'missing', '["contact_email"]'::jsonb
    );
  end if;

  v_quote := public.rq_create_quote(v_lead.id);

  return jsonb_build_object(
    'ok', true,
    'quote_token', v_quote ->> 'public_token',
    'quote_number', v_quote ->> 'quote_number',
    'quote_id', v_quote ->> 'quote_id'
  );
end;
$$;

create or replace function public.rq_public_quote(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_quote public.rq_quotes;
  v_c public.rq_contractors;
  v_lead public.rq_leads;
begin
  select * into v_quote from public.rq_quotes where public_token = p_token;
  if not found then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  select l.* into v_lead from public.rq_leads l where l.id = v_quote.lead_id;
  select * into v_c from public.rq_contractors where id = v_quote.contractor_id;

  if v_quote.status = 'sent' then
    update public.rq_quotes
    set status = 'viewed', viewed_at = now()
    where id = v_quote.id;

    insert into public.rq_quote_events (quote_id, lead_id, actor_role, action, detail)
    values (v_quote.id, v_quote.lead_id, 'customer', 'quote_viewed', 'Customer opened the quote');

    v_quote.status := 'viewed';
    v_quote.viewed_at := now();
  end if;

  return jsonb_build_object(
    'quote', to_jsonb(v_quote) - 'answers' - 'pricing' - 'notes',
    'answers', v_quote.answers,
    'pricing', v_quote.pricing,
    'items', coalesce((
      select jsonb_agg(to_jsonb(i) order by i.sort_order)
      from public.rq_quote_items i
      where i.quote_id = v_quote.id
    ), '[]'::jsonb),
    'customer', jsonb_build_object(
      'contact_name', v_lead.contact_name,
      'contact_email', v_lead.contact_email,
      'contact_phone', v_lead.contact_phone,
      'property_address', v_lead.property_address,
      'property_city', v_lead.property_city,
      'property_state', v_lead.property_state,
      'property_zip', v_lead.property_zip
    ),
    'contractor', jsonb_build_object(
      'company_name', v_c.company_name,
      'phone', v_c.phone,
      'website', v_c.website,
      'license_no', v_c.license_no,
      'address_line', v_c.address_line,
      'city', v_c.city,
      'state', v_c.state,
      'zip_code', v_c.zip_code,
      'logo_url', v_c.logo_url,
      'brand_color', v_c.brand_color,
      'terms', v_c.terms
    )
  );
end;
$$;

create or replace function public.rq_public_respond(p_token text, p_decision text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_quote public.rq_quotes;
  v_status text;
begin
  select * into v_quote from public.rq_quotes where public_token = p_token;
  if not found then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  if p_decision = 'accepted' then
    v_status := 'accepted';
  elsif p_decision = 'declined' then
    v_status := 'declined';
  else
    raise exception 'Unknown decision' using errcode = '22023';
  end if;

  update public.rq_quotes
  set status = v_status, responded_at = now()
  where id = v_quote.id;

  update public.rq_leads
  set status = case when v_status = 'accepted' then 'won' else 'lost' end
  where id = v_quote.lead_id;

  insert into public.rq_quote_events (quote_id, lead_id, actor_role, action, detail)
  values (v_quote.id, v_quote.lead_id, 'customer',
    case when v_status = 'accepted' then 'quote_accepted' else 'quote_declined' end,
    'Customer responded: ' || v_status);

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

revoke all on function public.rq_public_config() from public;
revoke all on function public.rq_public_start_lead(text, text) from public;
revoke all on function public.rq_public_lead(text) from public;
revoke all on function public.rq_public_save(text, jsonb, integer, jsonb) from public;
revoke all on function public.rq_public_submit(text) from public;
revoke all on function public.rq_public_quote(text) from public;
revoke all on function public.rq_public_respond(text, text) from public;

grant execute on function public.rq_public_config() to anon, authenticated;
grant execute on function public.rq_public_start_lead(text, text) to anon, authenticated;
grant execute on function public.rq_public_lead(text) to anon, authenticated;
grant execute on function public.rq_public_save(text, jsonb, integer, jsonb) to anon, authenticated;
grant execute on function public.rq_public_submit(text) to anon, authenticated;
grant execute on function public.rq_public_quote(text) to anon, authenticated;
grant execute on function public.rq_public_respond(text, text) to anon, authenticated;