-- Roofing Quote Generator :: expose the contractor on the staff quote detail
--
-- rq_quotes has no warranty_years and no currency column. Both live on
-- rq_contractors. rq_staff_get_quote returned neither, so the Edge Function read
-- quote.warranty_years (always undefined -> 0) and quote.currency (always
-- undefined -> "USD"), which meant the generated scope of work could state that
-- no warranty applies even when the contractor sells a 10 year warranty.
--
-- This adds a contractor key to the staff-only detail envelope. It is additive:
-- existing callers keep working and only gain a field. The columns that must
-- never reach the staff UI (owner_id) are stripped.

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

  select * into v_q
  from public.rq_quotes q
  where q.id = p_quote_id and q.contractor_id = v_cid;

  if v_q.id is null then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object(
    'quote', to_jsonb(v_q) - 'public_token',
    'contractor', (
      select to_jsonb(ct) - 'owner_id'
      from public.rq_contractors ct
      where ct.id = v_q.contractor_id
    ),
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

revoke all on function public.rq_staff_get_quote(uuid) from public;
grant execute on function public.rq_staff_get_quote(uuid) to authenticated;