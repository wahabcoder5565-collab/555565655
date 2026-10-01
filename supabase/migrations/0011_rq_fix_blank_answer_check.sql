-- Roofing Quote Generator :: fix the blank answer check
--
-- rq_public_save and rq_public_submit tested for an empty answer with
--   v_answers -> q.key <> ''::jsonb
-- but an empty string is not valid JSON, so casting it to jsonb raised
-- 22P02 and every answer save failed.
--
-- rq_coerce_answers already normalises a blank text answer to JSON null, and
-- jsonb -> key returns SQL NULL for a key that was never answered. Those two
-- cases are the only ones that mean "not answered", so they are what gets
-- tested.

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

revoke all on function public.rq_public_save(text, jsonb, integer, jsonb) from public;
revoke all on function public.rq_public_submit(text) from public;

grant execute on function public.rq_public_save(text, jsonb, integer, jsonb) to anon, authenticated;
grant execute on function public.rq_public_submit(text) to anon, authenticated;
