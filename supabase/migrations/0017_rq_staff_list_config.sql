-- Roofing Quote Generator :: staff readers for the effective rate card
--
-- The rate card and questionnaire editors need to display the *effective* rows,
-- meaning system defaults with the contractor's own overrides applied on top.
--
-- 0015 revoked rq_effective_rate_items and rq_effective_questions from
-- authenticated because they are SECURITY DEFINER, take an arbitrary contractor
-- uuid and carry no internal auth check, which made a cross-tenant rate card
-- read possible. That revocation stands. The problem it leaves behind is that
-- there is then no way for a logged-in contractor to read their own rate card
-- at all, because reading the table directly only surfaces the contractor's own
-- override rows under RLS and never the system rows they inherit from.
--
-- These two functions restore that read without reopening the leak: they take no
-- contractor id, resolve the caller through rq_my_contractor_id(), and project
-- only the fields the editors need. Each row is tagged with is_override so the
-- UI can distinguish inherited system pricing from a local edit.

create or replace function public.rq_staff_list_rate_items()
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
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', r.id,
        'code', r.code,
        'category', r.category,
        'label', r.label,
        'description', r.description,
        'unit', r.unit,
        'unit_cost', r.unit_cost,
        'unit_price', r.unit_price,
        'sort_order', r.sort_order,
        'is_active', r.is_active,
        'is_override', r.contractor_id is not null
      )
      order by r.category, r.sort_order, r.code
    )
    from public.rq_effective_rate_items(v_cid) r
  ), '[]'::jsonb);
end;
$$;

create or replace function public.rq_staff_list_questions()
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
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', q.id,
        'key', q.key,
        'section', q.section,
        'label', q.label,
        'help_text', q.help_text,
        'input_type', q.input_type,
        'unit', q.unit,
        'options', q.options,
        'required', q.required,
        'affects_price', q.affects_price,
        'min_value', q.min_value,
        'max_value', q.max_value,
        'step_value', q.step_value,
        'sort_order', q.sort_order,
        'is_active', q.is_active,
        'is_override', q.contractor_id is not null
      )
      order by q.section, q.sort_order, q.key
    )
    from public.rq_effective_questions(v_cid) q
  ), '[]'::jsonb);
end;
$$;

-- Granted to authenticated only. These are the two new entries in the allow-list
-- from 0015; anon has no business reading a rate card.
revoke all on function public.rq_staff_list_rate_items() from public, anon;
revoke all on function public.rq_staff_list_questions() from public, anon;
grant execute on function public.rq_staff_list_rate_items() to authenticated;
grant execute on function public.rq_staff_list_questions() to authenticated;