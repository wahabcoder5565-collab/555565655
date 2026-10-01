-- Roofing Quote Generator :: small shared helpers

-- Exactly one contractor is "primary". New public quote requests go to them.
-- Keeps the anonymous wizard pointed at a real business without an auth flow.
alter table public.rq_contractors
  add column if not exists is_primary boolean not null default false;

create or replace function public.rq_default_contractor_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
  from public.rq_contractors c
  order by c.is_primary desc, c.updated_at desc, c.created_at asc
  limit 1;
$$;

-- 192 bits of entropy, hex encoded. This string is the only credential an
-- anonymous customer ever holds, so it must not be guessable or enumerable.
create or replace function public.rq_new_token()
returns text
language sql
volatile
security definer
set search_path = ''
as $$
  select encode(extensions.gen_random_bytes(24), 'hex');
$$;

-- jsonb accessors that tolerate the string/number/bool sloppiness of values
-- arriving from a form post. Anything unparseable falls back to the default.
create or replace function public.rq_num(p_json jsonb, p_key text, p_default numeric)
returns numeric
language plpgsql
immutable
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

create or replace function public.rq_bool(p_json jsonb, p_key text, p_default boolean)
returns boolean
language plpgsql
immutable
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

create or replace function public.rq_txt(p_json jsonb, p_key text, p_default text)
returns text
language plpgsql
immutable
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

-- Appends one priced line to a jsonb array of line items.
create or replace function public.rq_add_item(
  p_items jsonb,
  p_category text,
  p_code text,
  p_label text,
  p_description text,
  p_qty numeric,
  p_unit text,
  p_unit_price numeric
)
returns jsonb
language plpgsql
immutable
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
as $$
  select case
    when p_warning is null or btrim(p_warning) = '' then p_warnings
    when p_warnings @> jsonb_build_array(p_warning) then p_warnings
    else p_warnings || jsonb_build_array(p_warning)
  end;
$$;

revoke all on function public.rq_default_contractor_id() from public;
revoke all on function public.rq_new_token() from public;

grant execute on function public.rq_default_contractor_id() to anon, authenticated;
grant execute on function public.rq_new_token() to anon, authenticated;

grant execute on function public.rq_num(jsonb, text, numeric) to anon, authenticated;
grant execute on function public.rq_bool(jsonb, text, boolean) to anon, authenticated;
grant execute on function public.rq_txt(jsonb, text, text) to anon, authenticated;
grant execute on function public.rq_add_item(jsonb, text, text, text, text, numeric, text, numeric) to anon, authenticated;
grant execute on function public.rq_add_warning(jsonb, text) to anon, authenticated;