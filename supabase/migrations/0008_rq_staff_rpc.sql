-- Roofing Quote Generator :: staff dashboard RPCs
--
-- Everything here is authenticated-only and every function resolves the
-- caller's own contractor first, so a staff member can never address another
-- contractor's rows. Revoked from PUBLIC so anon cannot call them at all.

-- The engine is priced against a specific rate card, so anon must only reach it
-- through rq_preview_quote, which always uses the default contractor.
revoke all on function public.rq_compute_quote(uuid, jsonb) from anon;
revoke all on function public.rq_rate_lookup(uuid, text) from anon;
revoke all on function public.rq_apply_totals(jsonb, jsonb, numeric) from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

create or replace function public.rq_staff_bootstrap()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_ensure_contractor();
  v_c public.rq_contractors;
  v_own_rates int;
  v_own_questions int;
begin
  select * into v_c from public.rq_contractors where id = v_cid;

  select count(*) into v_own_rates
  from public.rq_rate_items ri where ri.contractor_id = v_cid;
  select count(*) into v_own_questions
  from public.rq_questions q where q.contractor_id = v_cid;

  return jsonb_build_object(
    'contractor', to_jsonb(v_c) - 'owner_id',
    'rate_items', coalesce((
      select jsonb_agg(to_jsonb(ri) - 'contractor_id' order by ri.category, ri.sort_order, ri.code)
      from public.rq_effective_rate_items(v_cid) ri
    ), '[]'::jsonb),
    'questions', coalesce((
      select jsonb_agg(to_jsonb(q) - 'contractor_id' order by q.section, q.sort_order, q.key)
      from public.rq_effective_questions(v_cid) q
    ), '[]'::jsonb),
    'has_own_rates', v_own_rates > 0,
    'has_own_questions', v_own_questions > 0,
    'rate_item_count', v_own_rates,
    'question_count', v_own_questions
  );
end;
$$;

create or replace function public.rq_staff_save_settings(p_settings jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_ensure_contractor();
  v_c public.rq_contractors;
begin
  update public.rq_contractors c
  set company_name    = case when p_settings ? 'company_name'    then left(coalesce(public.rq_txt(p_settings, 'company_name', ''), ''), 160) else c.company_name end,
      contact_email   = case when p_settings ? 'contact_email'   then lower(left(coalesce(public.rq_txt(p_settings, 'contact_email', ''), ''), 200)) else c.contact_email end,
      phone           = case when p_settings ? 'phone'           then left(coalesce(public.rq_txt(p_settings, 'phone', ''), ''), 40) else c.phone end,
      license_no      = case when p_settings ? 'license_no'      then left(coalesce(public.rq_txt(p_settings, 'license_no', ''), ''), 60) else c.license_no end,
      website         = case when p_settings ? 'website'         then left(coalesce(public.rq_txt(p_settings, 'website', ''), ''), 200) else c.website end,
      address_line    = case when p_settings ? 'address_line'    then left(coalesce(public.rq_txt(p_settings, 'address_line', ''), ''), 200) else c.address_line end,
      city            = case when p_settings ? 'city'            then left(coalesce(public.rq_txt(p_settings, 'city', ''), ''), 100) else c.city end,
      state           = case when p_settings ? 'state'           then left(coalesce(public.rq_txt(p_settings, 'state', ''), ''), 40) else c.state end,
      zip_code        = case when p_settings ? 'zip_code'        then left(coalesce(public.rq_txt(p_settings, 'zip_code', ''), ''), 20) else c.zip_code end,
      currency        = case when p_settings ? 'currency'        then left(upper(coalesce(public.rq_txt(p_settings, 'currency', 'USD'), 'USD')), 3) else c.currency end,
      logo_url        = case when p_settings ? 'logo_url'        then left(coalesce(public.rq_txt(p_settings, 'logo_url', ''), ''), 400) else c.logo_url end,
      terms           = case when p_settings ? 'terms'           then left(coalesce(public.rq_txt(p_settings, 'terms', ''), ''), 4000) else c.terms end,
      brand_color     = case
                          when p_settings ? 'brand_color'
                            and public.rq_txt(p_settings, 'brand_color', '') ~ '^#[0-9a-fA-F]{6}$'
                            then public.rq_txt(p_settings, 'brand_color', c.brand_color)
                          else c.brand_color
                        end,
      waste_factor_pct = case when p_settings ? 'waste_factor_pct' then greatest(0, least(100, public.rq_num(p_settings, 'waste_factor_pct', c.waste_factor_pct))) else c.waste_factor_pct end,
      overhead_pct     = case when p_settings ? 'overhead_pct'     then greatest(0, least(500, public.rq_num(p_settings, 'overhead_pct', c.overhead_pct))) else c.overhead_pct end,
      profit_pct       = case when p_settings ? 'profit_pct'       then greatest(0, least(500, public.rq_num(p_settings, 'profit_pct', c.profit_pct))) else c.profit_pct end,
      contingency_pct  = case when p_settings ? 'contingency_pct'  then greatest(0, least(100, public.rq_num(p_settings, 'contingency_pct', c.contingency_pct))) else c.contingency_pct end,
      tax_pct          = case when p_settings ? 'tax_pct'          then greatest(0, least(100, public.rq_num(p_settings, 'tax_pct', c.tax_pct))) else c.tax_pct end,
      min_charge       = case when p_settings ? 'min_charge'       then greatest(0, public.rq_num(p_settings, 'min_charge', c.min_charge)) else c.min_charge end,
      deposit_pct      = case when p_settings ? 'deposit_pct'      then greatest(0, least(100, public.rq_num(p_settings, 'deposit_pct', c.deposit_pct))) else c.deposit_pct end,
      valid_days       = case when p_settings ? 'valid_days'       then greatest(1, least(365, public.rq_num(p_settings, 'valid_days', c.valid_days)::int)) else c.valid_days end,
      warranty_years   = case when p_settings ? 'warranty_years'   then greatest(0, least(100, public.rq_num(p_settings, 'warranty_years', c.warranty_years)::int)) else c.warranty_years end
  where c.id = v_cid
  returning * into v_c;

  return to_jsonb(v_c) - 'owner_id';
end;
$$;

-- ---------------------------------------------------------------------------
-- Rate card
-- ---------------------------------------------------------------------------

create or replace function public.rq_staff_save_rate_item(p_item jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_ensure_contractor();
  v_id uuid := nullif(public.rq_txt(p_item, 'id', ''), '')::uuid;
  v_code text := lower(btrim(coalesce(public.rq_txt(p_item, 'code', ''), '')));
  v_category text := lower(coalesce(public.rq_txt(p_item, 'category', 'material'), 'material'));
  v_unit text := lower(coalesce(public.rq_txt(p_item, 'unit', 'sqft'), 'sqft'));
  v_label text := btrim(coalesce(public.rq_txt(p_item, 'label', ''), ''));
  v_row public.rq_rate_items;
begin
  if v_code !~ '^[a-z0-9_]{2,60}$' then
    raise exception 'Rate code must be lowercase letters, digits and underscores' using errcode = '22023';
  end if;
  if v_category not in ('material', 'underlayment', 'accessory', 'teardown', 'disposal', 'labor', 'permit', 'protection') then
    raise exception 'Unknown category "%"', v_category using errcode = '22023';
  end if;
  if v_unit not in ('sqft', 'square', 'linear_ft', 'each', 'sheet', 'hour') then
    raise exception 'Unknown unit "%"', v_unit using errcode = '22023';
  end if;
  if v_label = '' then
    raise exception 'A label is required' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.rq_rate_items ri
    where ri.contractor_id = v_cid and ri.code = v_code
      and (v_id is null or ri.id <> v_id)
  ) then
    raise exception 'You already have a rate item with the code "%"', v_code using errcode = '23505';
  end if;

  -- Editing a shared system row writes an override copy for this contractor
  -- instead of mutating the template everyone else sees.
  if v_id is not null then
    select * into v_row from public.rq_rate_items ri
    where ri.id = v_id and ri.contractor_id = v_cid;
  end if;

  if v_row.id is null then
    insert into public.rq_rate_items (
      contractor_id, code, category, label, description, unit,
      unit_cost, unit_price, sort_order, is_active
    )
    values (
      v_cid, v_code, v_category, v_label,
      coalesce(public.rq_txt(p_item, 'description', ''), ''),
      v_unit,
      greatest(0, public.rq_num(p_item, 'unit_cost', 0)),
      greatest(0, public.rq_num(p_item, 'unit_price', 0)),
      public.rq_num(p_item, 'sort_order', 0)::int,
      public.rq_bool(p_item, 'is_active', true)
    )
    returning * into v_row;
  else
    update public.rq_rate_items ri
    set code = v_code,
        category = v_category,
        label = v_label,
        description = coalesce(public.rq_txt(p_item, 'description', ri.description), ri.description),
        unit = v_unit,
        unit_cost = case when p_item ? 'unit_cost'   then greatest(0, public.rq_num(p_item, 'unit_cost', ri.unit_cost)) else ri.unit_cost end,
        unit_price = case when p_item ? 'unit_price' then greatest(0, public.rq_num(p_item, 'unit_price', ri.unit_price)) else ri.unit_price end,
        sort_order = case when p_item ? 'sort_order' then public.rq_num(p_item, 'sort_order', ri.sort_order)::int else ri.sort_order end,
        is_active = case when p_item ? 'is_active' then public.rq_bool(p_item, 'is_active', ri.is_active) else ri.is_active end
    where ri.id = v_row.id
    returning * into v_row;
  end if;

  return to_jsonb(v_row) - 'contractor_id';
end;
$$;

create or replace function public.rq_staff_delete_rate_item(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_ensure_contractor();
  v_row public.rq_rate_items;
begin
  select * into v_row from public.rq_rate_items ri
  where ri.id = p_id and ri.contractor_id = v_cid;

  if v_row.id is not null then
    delete from public.rq_rate_items ri where ri.id = v_row.id;
    return jsonb_build_object('ok', true, 'action', 'deleted', 'code', v_row.code);
  end if;

  -- Hiding a shared system line is done by writing an inactive override,
  -- never by touching the template.
  select * into v_row from public.rq_rate_items ri
  where ri.id = p_id and ri.contractor_id is null;

  if v_row.id is not null then
    update public.rq_rate_items ri
    set is_active = false
    where ri.contractor_id = v_cid and ri.code = v_row.code;

    if not found then
      insert into public.rq_rate_items (
        contractor_id, code, category, label, description, unit,
        unit_cost, unit_price, sort_order, is_active
      )
      values (
        v_cid, v_row.code, v_row.category, v_row.label, v_row.description, v_row.unit,
        v_row.unit_cost, v_row.unit_price, v_row.sort_order, false
      )
      returning * into v_row;
    end if;

    return jsonb_build_object('ok', true, 'action', 'hidden', 'code', v_row.code);
  end if;

  raise exception 'Rate item not found' using errcode = 'no_data_found';
end;
$$;

create or replace function public.rq_staff_reset_rate_items()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_ensure_contractor();
  v_removed int;
begin
  delete from public.rq_rate_items ri where ri.contractor_id = v_cid;
  get diagnostics v_removed = row_count;

  return jsonb_build_object(
    'ok', true,
    'removed', v_removed,
    'rate_items', coalesce((
      select jsonb_agg(to_jsonb(ri) - 'contractor_id' order by ri.category, ri.sort_order, ri.code)
      from public.rq_effective_rate_items(v_cid) ri
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Questionnaire
-- ---------------------------------------------------------------------------

create or replace function public.rq_staff_save_question(p_question jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_ensure_contractor();
  v_id uuid := nullif(public.rq_txt(p_question, 'id', ''), '')::uuid;
  v_key text := lower(btrim(coalesce(public.rq_txt(p_question, 'key', ''), '')));
  v_section text := lower(coalesce(public.rq_txt(p_question, 'section', 'roof'), 'roof'));
  v_type text := lower(coalesce(public.rq_txt(p_question, 'input_type', 'text'), 'text'));
  v_label text := btrim(coalesce(public.rq_txt(p_question, 'label', ''), ''));
  v_options jsonb;
  v_row public.rq_questions;
begin
  if v_key !~ '^[a-z0-9_]{2,60}$' then
    raise exception 'Question key must be lowercase letters, digits and underscores' using errcode = '22023';
  end if;
  if v_type not in ('number', 'select', 'boolean', 'text', 'multi_select') then
    raise exception 'Unknown input type "%"', v_type using errcode = '22023';
  end if;
  if v_label = '' then
    raise exception 'A label is required' using errcode = '22023';
  end if;
  if v_type in ('select', 'multi_select') then
    v_options := coalesce(p_question -> 'options', '[]'::jsonb);
    if jsonb_typeof(v_options) <> 'array' then
      raise exception 'Options must be a JSON array' using errcode = '22023';
    end if;
    v_options := coalesce((
      select jsonb_agg(jsonb_build_array(value)) from jsonb_array_elements(v_options)
    ), '[]'::jsonb);
  else
    v_options := '[]'::jsonb;
  end if;

  if exists (
    select 1 from public.rq_questions q
    where q.contractor_id = v_cid and q.key = v_key
      and (v_id is null or q.id <> v_id)
  ) then
    raise exception 'You already have a question with the key "%"', v_key using errcode = '23505';
  end if;

  if v_id is not null then
    select * into v_row from public.rq_questions q
    where q.id = v_id and q.contractor_id = v_cid;
  end if;

  if v_row.id is null then
    insert into public.rq_questions (
      contractor_id, key, section, label, help_text, input_type, unit, options,
      required, affects_price, min_value, max_value, step_value, sort_order, is_active
    )
    values (
      v_cid, v_key, v_section, v_label,
      coalesce(public.rq_txt(p_question, 'help_text', ''), ''),
      v_type,
      coalesce(public.rq_txt(p_question, 'unit', ''), ''),
      v_options,
      public.rq_bool(p_question, 'required', false),
      public.rq_bool(p_question, 'affects_price', true),
      nullif(public.rq_num(p_question, 'min_value', 0), 0),
      nullif(public.rq_num(p_question, 'max_value', 0), 0),
      nullif(public.rq_num(p_question, 'step_value', 0), 0),
      public.rq_num(p_question, 'sort_order', 100)::int,
      public.rq_bool(p_question, 'is_active', true)
    )
    returning * into v_row;
  else
    update public.rq_questions q
    set key = v_key,
        section = v_section,
        label = v_label,
        help_text = coalesce(public.rq_txt(p_question, 'help_text', q.help_text), q.help_text),
        input_type = v_type,
        unit = case when p_question ? 'unit' then coalesce(public.rq_txt(p_question, 'unit', q.unit), q.unit) else q.unit end,
        options = v_options,
        required = case when p_question ? 'required' then public.rq_bool(p_question, 'required', q.required) else q.required end,
        affects_price = case when p_question ? 'affects_price' then public.rq_bool(p_question, 'affects_price', q.affects_price) else q.affects_price end,
        min_value = case when p_question ? 'min_value' then nullif(public.rq_num(p_question, 'min_value', 0), 0) else q.min_value end,
        max_value = case when p_question ? 'max_value' then nullif(public.rq_num(p_question, 'max_value', 0), 0) else q.max_value end,
        step_value = case when p_question ? 'step_value' then nullif(public.rq_num(p_question, 'step_value', 0), 0) else q.step_value end,
        sort_order = case when p_question ? 'sort_order' then public.rq_num(p_question, 'sort_order', q.sort_order)::int else q.sort_order end,
        is_active = case when p_question ? 'is_active' then public.rq_bool(p_question, 'is_active', q.is_active) else q.is_active end
    where q.id = v_row.id
    returning * into v_row;
  end if;

  return to_jsonb(v_row) - 'contractor_id';
end;
$$;

create or replace function public.rq_staff_delete_question(p_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_ensure_contractor();
  v_row public.rq_questions;
begin
  select * into v_row from public.rq_questions q
  where q.id = p_id and q.contractor_id = v_cid;

  if v_row.id is not null then
    delete from public.rq_questions q where q.id = v_row.id;
    return jsonb_build_object('ok', true, 'action', 'deleted', 'key', v_row.key);
  end if;

  select * into v_row from public.rq_questions q
  where q.id = p_id and q.contractor_id is null;

  if v_row.id is not null then
    update public.rq_questions q
    set is_active = false
    where q.contractor_id = v_cid and q.key = v_row.key;

    if not found then
      insert into public.rq_questions (
        contractor_id, key, section, label, help_text, input_type, unit, options,
        required, affects_price, min_value, max_value, step_value, sort_order, is_active
      )
      values (
        v_cid, v_row.key, v_row.section, v_row.label, v_row.help_text, v_row.input_type,
        v_row.unit, v_row.options, v_row.required, v_row.affects_price,
        v_row.min_value, v_row.max_value, v_row.step_value, v_row.sort_order, false
      )
      returning * into v_row;
    end if;

    return jsonb_build_object('ok', true, 'action', 'hidden', 'key', v_row.key);
  end if;

  raise exception 'Question not found' using errcode = 'no_data_found';
end;
$$;

create or replace function public.rq_staff_reset_questions()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid := public.rq_ensure_contractor();
  v_removed int;
begin
  delete from public.rq_questions q where q.contractor_id = v_cid;
  get diagnostics v_removed = row_count;

  return jsonb_build_object(
    'ok', true,
    'removed', v_removed,
    'questions', coalesce((
      select jsonb_agg(to_jsonb(q) - 'contractor_id' order by q.section, q.sort_order, q.key)
      from public.rq_effective_questions(v_cid) q
    ), '[]'::jsonb)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Leads and quotes
-- ---------------------------------------------------------------------------

-- Turns a user typed search box value into a safe ILIKE pattern. The term is
-- always a bound parameter, so only LIKE metacharacters need escaping.
create or replace function public.rq_like(p_term text)
returns text
language sql
immutable
as $$
  select case
    when p_term is null or btrim(p_term) = '' then null
    else '%' || replace(replace(replace(btrim(p_term), '\', '\\'), '%', '\%'), '_', '\_') || '%'
  end;
$$;

create or replace function public.rq_staff_list_leads(
  p_status text default null,
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_rows jsonb;
  v_total bigint;
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_like text := public.rq_like(p_search);
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    return jsonb_build_object('rows', '[]'::jsonb, 'total', 0);
  end if;
  if v_status = 'all' then
    v_status := null;
  end if;

  select count(*)
    into v_total
  from public.rq_leads l
  where l.contractor_id = v_cid
    and (v_status is null or l.status = v_status)
    and (
      v_like is null
      or l.contact_name ilike v_like
      or l.contact_email ilike v_like
      or l.contact_phone ilike v_like
      or l.property_address ilike v_like
      or exists (
        select 1 from public.rq_quotes q
        where q.lead_id = l.id and q.quote_number ilike v_like
      )
    );

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select l.id, l.public_token, l.status, l.contact_name, l.contact_email, l.contact_phone,
           l.property_address, l.property_city, l.property_state, l.property_zip,
           l.project_type, l.completion, l.utm_source, l.utm_campaign,
           l.created_at, l.submitted_at,
           (select count(*) from public.rq_quotes q where q.lead_id = l.id) as quote_count,
           (select q.id from public.rq_quotes q where q.lead_id = l.id
             order by q.created_at desc limit 1) as latest_quote_id,
           (select q.quote_number from public.rq_quotes q where q.lead_id = l.id
             order by q.created_at desc limit 1) as latest_quote_number,
           (select q.total from public.rq_quotes q where q.lead_id = l.id
             order by q.created_at desc limit 1) as latest_quote_total,
           (select q.status from public.rq_quotes q where q.lead_id = l.id
             order by q.created_at desc limit 1) as latest_quote_status
    from public.rq_leads l
    where l.contractor_id = v_cid
      and (v_status is null or l.status = v_status)
      and (
        v_like is null
        or l.contact_name ilike v_like
        or l.contact_email ilike v_like
        or l.contact_phone ilike v_like
        or l.property_address ilike v_like
        or exists (
          select 1 from public.rq_quotes q
          where q.lead_id = l.id and q.quote_number ilike v_like
        )
      )
    order by l.created_at desc
    limit greatest(1, least(200, coalesce(p_limit, 50)))
    offset greatest(0, coalesce(p_offset, 0))
  ) x;

  return jsonb_build_object('rows', v_rows, 'total', v_total);
end;
$$;

create or replace function public.rq_staff_get_lead(p_lead_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_lead public.rq_leads;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  select * into v_lead from public.rq_leads l
  where l.id = p_lead_id and l.contractor_id = v_cid;

  if v_lead.id is null then
    raise exception 'Lead not found' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object(
    'lead', to_jsonb(v_lead),
    'quotes', coalesce((
      select jsonb_agg(to_jsonb(q) order by q.created_at desc)
      from public.rq_quotes q where q.lead_id = v_lead.id
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.rq_staff_set_lead_status(p_lead_id uuid, p_status text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_status text := lower(coalesce(p_status, ''));
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if v_status not in ('draft', 'submitted', 'quoted', 'contacted', 'won', 'lost') then
    raise exception 'Unknown lead status "%"', v_status using errcode = '22023';
  end if;

  update public.rq_leads l
  set status = v_status
  where l.id = p_lead_id and l.contractor_id = v_cid;

  if not found then
    raise exception 'Lead not found' using errcode = 'no_data_found';
  end if;

  insert into public.rq_quote_events (quote_id, lead_id, actor_id, actor_role, action, detail)
  values (null, p_lead_id, auth.uid(), 'staff', 'lead_status_changed', 'Lead marked as ' || v_status);

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

create or replace function public.rq_staff_list_quotes(
  p_status text default null,
  p_search text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_rows jsonb;
  v_total bigint;
  v_status text := nullif(btrim(coalesce(p_status, '')), '');
  v_like text := public.rq_like(p_search);
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    return jsonb_build_object('rows', '[]'::jsonb, 'total', 0);
  end if;
  if v_status = 'all' then
    v_status := null;
  end if;

  select count(*)
    into v_total
  from public.rq_quotes q
  join public.rq_leads l on l.id = q.lead_id
  where q.contractor_id = v_cid
    and (v_status is null or q.status = v_status)
    and (
      v_like is null
      or q.quote_number ilike v_like
      or l.contact_name ilike v_like
      or l.property_address ilike v_like
    );

  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc), '[]'::jsonb)
    into v_rows
  from (
    select q.id, q.public_token, q.quote_number, q.status, q.project_type,
           q.roof_area_sqft, q.total, q.deposit_amount, q.price_per_sqft,
           q.ai_status, q.created_at, q.viewed_at, q.responded_at, q.valid_until,
           q.lead_id,
           l.contact_name, l.property_address, l.property_city, l.property_state, l.property_zip
    from public.rq_quotes q
    join public.rq_leads l on l.id = q.lead_id
    where q.contractor_id = v_cid
      and (v_status is null or q.status = v_status)
      and (
        v_like is null
        or q.quote_number ilike v_like
        or l.contact_name ilike v_like
        or l.property_address ilike v_like
      )
    order by q.created_at desc
    limit greatest(1, least(200, coalesce(p_limit, 50)))
    offset greatest(0, coalesce(p_offset, 0))
  ) x;

  return jsonb_build_object('rows', v_rows, 'total', v_total);
end;
$$;

create or replace function public.rq_staff_get_quote(p_quote_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_q public.rq_quotes;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  select * into v_q from public.rq_quotes q
  where q.id = p_quote_id and q.contractor_id = v_cid;

  if v_q.id is null then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object(
    'quote', to_jsonb(v_q) - 'public_token',
    'lead', (select to_jsonb(l) from public.rq_leads l where l.id = v_q.lead_id),
    'items', coalesce((
      select jsonb_agg(to_jsonb(i) order by i.sort_order)
      from public.rq_quote_items i where i.quote_id = v_q.id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(to_jsonb(e) - 'actor_id' order by e.created_at desc)
      from public.rq_quote_events e
      where e.quote_id = v_q.id or e.lead_id = v_q.lead_id
    ), '[]'::jsonb),
    'public_url_token', v_q.public_token
  );
end;
$$;

create or replace function public.rq_staff_set_quote_status(p_quote_id uuid, p_status text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_status text := lower(coalesce(p_status, ''));
  v_quote public.rq_quotes;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;
  if v_status not in ('draft', 'sent', 'viewed', 'accepted', 'declined', 'expired') then
    raise exception 'Unknown quote status "%"', v_status using errcode = '22023';
  end if;

  update public.rq_quotes q
  set status = v_status,
      sent_at = case when v_status = 'sent' and q.sent_at is null then now() else q.sent_at end,
      viewed_at = case when v_status = 'viewed' and q.viewed_at is null then now() else q.viewed_at end
  where q.id = p_quote_id and q.contractor_id = v_cid
  returning * into v_quote;

  if v_quote.id is null then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  if v_status in ('accepted', 'declined') then
    update public.rq_leads l
    set status = case when v_status = 'accepted' then 'won' else 'lost' end
    where l.id = v_quote.lead_id;
  end if;

  insert into public.rq_quote_events (quote_id, lead_id, actor_id, actor_role, action, detail)
  values (v_quote.id, v_quote.lead_id, auth.uid(), 'staff', 'quote_status_changed',
    'Marked as ' || v_status);

  return jsonb_build_object('ok', true, 'status', v_status);
end;
$$;

create or replace function public.rq_staff_save_quote_items(p_quote_id uuid, p_items jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_quote public.rq_quotes;
  v_item jsonb;
  v_clean jsonb := '[]'::jsonb;
  v_sort int := 0;
  v_totals jsonb;
  v_qty numeric;
  v_price numeric;
  v_label text;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  select * into v_quote from public.rq_quotes q
  where q.id = p_quote_id and q.contractor_id = v_cid;
  if v_quote.id is null then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;
  if jsonb_typeof(p_items) <> 'array' then
    raise exception 'Line items must be a JSON array' using errcode = '22023';
  end if;

  for v_item in select e.value from jsonb_array_elements(p_items) e
  loop
    v_label := btrim(coalesce(public.rq_txt(v_item, 'label', ''), ''));
    if v_label = '' then
      raise exception 'Every line item needs a label' using errcode = '22023';
    end if;
    v_qty := greatest(0, public.rq_num(v_item, 'quantity', 0));
    v_price := greatest(0, public.rq_num(v_item, 'unit_price', 0));

    v_clean := v_clean || jsonb_build_array(
      jsonb_build_object(
        'category', left(coalesce(public.rq_txt(v_item, 'category', 'accessory'), 'accessory'), 40),
        'code', left(coalesce(public.rq_txt(v_item, 'code', ''), ''), 60),
        'label', left(v_label, 200),
        'description', left(coalesce(public.rq_txt(v_item, 'description', ''), ''), 500),
        'quantity', round(v_qty, 2),
        'unit', left(coalesce(public.rq_txt(v_item, 'unit', 'each'), 'each'), 20),
        'unit_price', round(v_price, 2),
        'line_total', round(v_qty * v_price, 2),
        'sort_order', v_sort
      )
    );
    v_sort := v_sort + 10;
  end loop;

  -- Same markup ladder the engine uses, so a hand-edited quote and a generated
  -- quote can never disagree about the total.
  v_totals := public.rq_apply_totals(v_clean, v_quote.pricing, v_quote.roof_area_sqft);

  delete from public.rq_quote_items i where i.quote_id = v_quote.id;

  for v_item in select e.value from jsonb_array_elements(v_clean) e
  loop
    insert into public.rq_quote_items (
      quote_id, category, code, label, description,
      quantity, unit, unit_price, line_total, sort_order
    )
    values (
      v_quote.id,
      v_item ->> 'category',
      v_item ->> 'code',
      v_item ->> 'label',
      v_item ->> 'description',
      (v_item ->> 'quantity')::numeric,
      v_item ->> 'unit',
      (v_item ->> 'unit_price')::numeric,
      (v_item ->> 'line_total')::numeric,
      (v_item ->> 'sort_order')::int
    );
  end loop;

  update public.rq_quotes q
  set subtotal = (v_totals ->> 'subtotal')::numeric,
      contingency_total = (v_totals ->> 'contingency_total')::numeric,
      overhead_total = (v_totals ->> 'overhead_total')::numeric,
      profit_total = (v_totals ->> 'profit_total')::numeric,
      tax_total = (v_totals ->> 'tax_total')::numeric,
      min_charge_adjustment = (v_totals ->> 'min_charge_adjustment')::numeric,
      total = (v_totals ->> 'total')::numeric,
      deposit_amount = (v_totals ->> 'deposit_amount')::numeric,
      price_per_sqft = (v_totals ->> 'price_per_sqft')::numeric,
      -- The written scope described the old line items, so it has to be
      -- written again rather than left looking current.
      ai_status = 'pending'
  where q.id = v_quote.id;

  insert into public.rq_quote_events (quote_id, lead_id, actor_id, actor_role, action, detail)
  values (v_quote.id, v_quote.lead_id, auth.uid(), 'staff', 'items_edited',
    jsonb_array_length(v_clean)::text || ' line items, total ' || (v_totals ->> 'total')::text);

  return jsonb_build_object(
    'ok', true,
    'items', v_clean,
    'totals', v_totals
  );
end;
$$;

create or replace function public.rq_staff_save_quote_notes(p_quote_id uuid, p_notes text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  update public.rq_quotes q
  set notes = left(coalesce(p_notes, ''), 8000)
  where q.id = p_quote_id and q.contractor_id = v_cid;

  if not found then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.rq_staff_regenerate_quote(p_lead_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_old public.rq_quotes;
  v_new jsonb;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  if not exists (select 1 from public.rq_leads l where l.id = p_lead_id and l.contractor_id = v_cid) then
    raise exception 'Lead not found' using errcode = 'no_data_found';
  end if;

  -- Re-pricing replaces the quote, so any still-open version is retired rather
  -- than left sitting next to the new one with a different number.
  for v_old in
    select * from public.rq_quotes q
    where q.lead_id = p_lead_id and q.status in ('draft', 'sent', 'viewed')
  loop
    update public.rq_quotes q set status = 'expired' where q.id = v_old.id;
    insert into public.rq_quote_events (quote_id, lead_id, actor_id, actor_role, action, detail)
    values (v_old.id, v_old.lead_id, auth.uid(), 'staff', 'quote_superseded',
      v_old.quote_number || ' replaced by a re-priced quote');
  end loop;

  v_new := public.rq_create_quote(p_lead_id);

  insert into public.rq_quote_events (quote_id, lead_id, actor_id, actor_role, action, detail)
  values ((v_new ->> 'quote_id')::uuid, p_lead_id, auth.uid(), 'staff', 'quote_repriced',
    'Re-priced to ' || (v_new ->> 'quote_number')::text);

  return v_new;
end;
$$;

create or replace function public.rq_staff_save_ai(p_quote_id uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  update public.rq_quotes q
  set ai_scope_of_work = left(coalesce(public.rq_txt(p_payload, 'scope_of_work', ''), ''), 12000),
      ai_summary = left(coalesce(public.rq_txt(p_payload, 'summary', ''), ''), 2000),
      ai_recommendations = coalesce(p_payload -> 'recommendations', '[]'::jsonb),
      ai_risk_notes = coalesce(p_payload -> 'risk_notes', '[]'::jsonb),
      ai_engine = left(coalesce(public.rq_txt(p_payload, 'engine', 'rules'), 'rules'), 40),
      ai_model = nullif(left(coalesce(public.rq_txt(p_payload, 'model', ''), ''), 120), ''),
      ai_status = 'ready',
      ai_error = null,
      ai_generated_at = now()
  where q.id = p_quote_id and q.contractor_id = v_cid;

  if not found then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  insert into public.rq_quote_events (quote_id, lead_id, actor_id, actor_role, action, detail)
  select q.id, q.lead_id, auth.uid(), 'system', 'ai_generated',
    'Scope of work written by ' || q.ai_engine
  from public.rq_quotes q where q.id = p_quote_id;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.rq_staff_log_event(
  p_quote_id uuid,
  p_action text,
  p_detail text default ''
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_quote public.rq_quotes;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  select * into v_quote from public.rq_quotes q
  where q.id = p_quote_id and q.contractor_id = v_cid;
  if v_quote.id is null then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  insert into public.rq_quote_events (quote_id, lead_id, actor_id, actor_role, action, detail)
  values (v_quote.id, v_quote.lead_id, auth.uid(), 'staff',
    left(btrim(coalesce(p_action, 'note')), 80), left(coalesce(p_detail, ''), 1000));

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.rq_staff_dashboard_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    return jsonb_build_object('leads', 0, 'quotes', 0);
  end if;

  return jsonb_build_object(
    'leads_total', (select count(*) from public.rq_leads l where l.contractor_id = v_cid),
    'leads_open', (select count(*) from public.rq_leads l
      where l.contractor_id = v_cid and l.status in ('draft', 'submitted', 'quoted', 'contacted')),
    'leads_30d', (select count(*) from public.rq_leads l
      where l.contractor_id = v_cid and l.created_at > now() - interval '30 days'),
    'leads_by_status', coalesce((
      select jsonb_object_agg(l.status, l.n) from (
        select l.status, count(*) as n from public.rq_leads l
        where l.contractor_id = v_cid group by l.status
      ) l
    ), '{}'::jsonb),
    'quotes_total', (select count(*) from public.rq_quotes q where q.contractor_id = v_cid),
    'quotes_by_status', coalesce((
      select jsonb_object_agg(q.status, q.n) from (
        select q.status, count(*) as n from public.rq_quotes q
        where q.contractor_id = v_cid group by q.status
      ) q
    ), '{}'::jsonb),
    'pipeline_value', (select coalesce(sum(q.total), 0) from public.rq_quotes q
      where q.contractor_id = v_cid and q.status in ('sent', 'viewed')),
    'won_value', (select coalesce(sum(q.total), 0) from public.rq_quotes q
      where q.contractor_id = v_cid and q.status = 'accepted'),
    'average_quote', (select coalesce(round(avg(q.total), 2), 0) from public.rq_quotes q
      where q.contractor_id = v_cid and q.status in ('sent', 'viewed', 'accepted')),
    'win_rate', coalesce((
      select round(100.0 * count(*) filter (where q.status = 'accepted') / greatest(1, count(*)), 1)
      from public.rq_quotes q
      where q.contractor_id = v_cid and q.status in ('accepted', 'declined')
    ), 0),
    'ai_pending', (select count(*) from public.rq_quotes q
      where q.contractor_id = v_cid and q.ai_status = 'pending'),
    'ai_failed', (select count(*) from public.rq_quotes q
      where q.contractor_id = v_cid and q.ai_status = 'failed')
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants. Authenticated only, and none of this is reachable by anon.
-- ---------------------------------------------------------------------------
revoke all on function public.rq_like(text) from public;
revoke all on function public.rq_staff_bootstrap() from public;
revoke all on function public.rq_staff_save_settings(jsonb) from public;
revoke all on function public.rq_staff_save_rate_item(jsonb) from public;
revoke all on function public.rq_staff_delete_rate_item(uuid) from public;
revoke all on function public.rq_staff_reset_rate_items() from public;
revoke all on function public.rq_staff_save_question(jsonb) from public;
revoke all on function public.rq_staff_delete_question(uuid) from public;
revoke all on function public.rq_staff_reset_questions() from public;
revoke all on function public.rq_staff_list_leads(text, text, integer, integer) from public;
revoke all on function public.rq_staff_get_lead(uuid) from public;
revoke all on function public.rq_staff_set_lead_status(uuid, text) from public;
revoke all on function public.rq_staff_list_quotes(text, text, integer, integer) from public;
revoke all on function public.rq_staff_get_quote(uuid) from public;
revoke all on function public.rq_staff_set_quote_status(uuid, text) from public;
revoke all on function public.rq_staff_save_quote_items(uuid, jsonb) from public;
revoke all on function public.rq_staff_save_quote_notes(uuid, text) from public;
revoke all on function public.rq_staff_regenerate_quote(uuid) from public;
revoke all on function public.rq_staff_save_ai(uuid, jsonb) from public;
revoke all on function public.rq_staff_log_event(uuid, text, text) from public;
revoke all on function public.rq_staff_dashboard_stats() from public;

grant execute on function
  public.rq_staff_bootstrap(),
  public.rq_staff_save_settings(jsonb),
  public.rq_staff_save_rate_item(jsonb),
  public.rq_staff_delete_rate_item(uuid),
  public.rq_staff_reset_rate_items(),
  public.rq_staff_save_question(jsonb),
  public.rq_staff_delete_question(uuid),
  public.rq_staff_reset_questions(),
  public.rq_staff_list_leads(text, text, integer, integer),
  public.rq_staff_get_lead(uuid),
  public.rq_staff_set_lead_status(uuid, text),
  public.rq_staff_list_quotes(text, text, integer, integer),
  public.rq_staff_get_quote(uuid),
  public.rq_staff_set_quote_status(uuid, text),
  public.rq_staff_save_quote_items(uuid, jsonb),
  public.rq_staff_save_quote_notes(uuid, text),
  public.rq_staff_regenerate_quote(uuid),
  public.rq_staff_save_ai(uuid, jsonb),
  public.rq_staff_log_event(uuid, text, text),
  public.rq_staff_dashboard_stats()
to authenticated;
