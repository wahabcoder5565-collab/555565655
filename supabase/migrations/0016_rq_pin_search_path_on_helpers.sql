-- Roofing Quote Generator :: pin search_path on the pure jsonb helpers
--
-- 0015 closed the execute surface. These seven functions are the last rq_
-- objects the security advisor still reports, under
-- function_search_path_mutable: they were created without SET search_path, so
-- they resolve builtins through whatever search_path happens to be in effect at
-- call time.
--
-- They are not SECURITY DEFINER and, since 0015, hold no grant for anon or
-- authenticated at all -- they are reachable only from inside the definer
-- functions that own them. So this is hygiene rather than an open hole, but it
-- is cheap to close and it removes the last rq_ finding from the advisor.
--
-- Every body below was copied verbatim from the live definitions. The only
-- change is the added `set search_path = ''`. That is safe here because each
-- body references nothing outside pg_catalog: the sole cross-function call is
-- rq_apply_totals -> public.rq_num, which is already schema-qualified, and
-- CREATE OR REPLACE preserves both the ownership and the (empty) ACL that 0015
-- established.

create or replace function public.rq_num(p_json jsonb, p_key text, p_default numeric)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_raw jsonb;
begin
  if p_json is null then
    return p_default;
  end if;
  v_raw := p_json -> p_key;
  if v_raw is null or v_raw = 'null'::jsonb then
    return p_default;
  end if;
  if jsonb_typeof(v_raw) = 'number' then
    return (v_raw #>> '{}')::numeric;
  end if;
  if jsonb_typeof(v_raw) = 'string' then
    begin
      return nullif(trim(both '"' from v_raw #>> '{}'), '')::numeric;
    exception when others then
      return p_default;
    end;
  end if;
  if jsonb_typeof(v_raw) = 'boolean' then
    return case when (v_raw #>> '{}') = 'true' then 1 else 0 end;
  end if;
  return p_default;
end;
$$;

create or replace function public.rq_txt(p_json jsonb, p_key text, p_default text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_raw jsonb;
begin
  if p_json is null then
    return p_default;
  end if;
  v_raw := p_json -> p_key;
  if v_raw is null or v_raw = 'null'::jsonb then
    return p_default;
  end if;
  if jsonb_typeof(v_raw) = 'string' then
    return nullif(trim(v_raw #>> '{}'), '');
  end if;
  return v_raw #>> '{}';
end;
$$;

create or replace function public.rq_bool(p_json jsonb, p_key text, p_default boolean)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_raw jsonb;
begin
  if p_json is null then
    return p_default;
  end if;
  v_raw := p_json -> p_key;
  if v_raw is null or v_raw = 'null'::jsonb then
    return p_default;
  end if;
  if jsonb_typeof(v_raw) = 'boolean' then
    return (v_raw #>> '{}')::boolean;
  end if;
  if jsonb_typeof(v_raw) = 'number' then
    return (v_raw #>> '{}')::numeric <> 0;
  end if;
  if jsonb_typeof(v_raw) = 'string' then
    return lower(v_raw #>> '{}') in ('true', 't', 'yes', 'y', 'on', '1');
  end if;
  return p_default;
end;
$$;

create or replace function public.rq_add_item(
  p_items jsonb, p_category text, p_code text, p_label text,
  p_description text, p_qty numeric, p_unit text, p_unit_price numeric
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_qty numeric := round(coalesce(p_qty, 0), 2);
  v_price numeric := round(coalesce(p_unit_price, 0), 2);
begin
  if v_qty <= 0 then
    return p_items;
  end if;
  return p_items || jsonb_build_array(
    jsonb_build_object(
      'category', p_category,
      'code', p_code,
      'label', p_label,
      'description', p_description,
      'quantity', v_qty,
      'unit', p_unit,
      'unit_price', v_price,
      'line_total', round(v_qty * v_price, 2)
    )
  );
end;
$$;

create or replace function public.rq_add_warning(p_warnings jsonb, p_warning text)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case
    when p_warning is null or btrim(p_warning) = '' then p_warnings
    when p_warnings @> jsonb_build_array(p_warning) then p_warnings
    else p_warnings || jsonb_build_array(p_warning)
  end;
$$;

create or replace function public.rq_apply_totals(p_items jsonb, p_pricing jsonb, p_area numeric)
returns jsonb
language plpgsql
immutable
set search_path = ''
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

-- Escapes LIKE metacharacters so a search term is matched literally.
create or replace function public.rq_like(p_term text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when p_term is null or btrim(p_term) = '' then null
    else '%' || replace(replace(replace(btrim(p_term), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  end;
$$;

-- Re-assert the 0015 posture. CREATE OR REPLACE keeps the existing ACL, but
-- stating it here means this file alone produces the intended surface and a
-- future edit that re-adds a grant cannot slip through unnoticed.
revoke all on function public.rq_num(jsonb, text, numeric) from anon, authenticated;
revoke all on function public.rq_txt(jsonb, text, text) from anon, authenticated;
revoke all on function public.rq_bool(jsonb, text, boolean) from anon, authenticated;
revoke all on function public.rq_add_item(jsonb, text, text, text, text, numeric, text, numeric) from anon, authenticated;
revoke all on function public.rq_add_warning(jsonb, text) from anon, authenticated;
revoke all on function public.rq_apply_totals(jsonb, jsonb, numeric) from anon, authenticated;
revoke all on function public.rq_like(text) from anon, authenticated;