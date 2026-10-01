-- Roofing Quote Generator :: revoke the default PUBLIC execute grant
--
-- Postgres grants EXECUTE on every newly created function to the PUBLIC
-- pseudo-role. 0013 and 0014 only revoked from the named roles `anon` and
-- `authenticated`, which reads like it removes access but does not: PUBLIC is
-- not one of the roles you revoke from, and revoking from a named role leaves
-- the wider PUBLIC grant sitting underneath it. So through 0014 every rq_
-- function was still executable by PUBLIC.
--
-- This migration fixes that by sweeping the PUBLIC grant off every rq_ function
-- and then re-granting an explicit allow-list. The allow-list is the source of
-- truth for the whole API surface, so adding a function does not accidentally
-- publish it.
--
-- While auditing that surface a second, real issue surfaced. The internal
-- helpers rq_effective_rate_items, rq_rate_lookup, rq_coerce_answers and
-- rq_compute_quote are all SECURITY DEFINER, take an arbitrary contractor uuid
-- and carry no internal auth check of their own (see the 0013 header). 0014
-- removed only the anon grant, leaving auth_exec = true, so any authenticated
-- staff user could pass a different contractor's uuid and read that
-- contractor's rate card or recompute their quote. On a shared project with
-- per-contractor overrides that is a cross-tenant read, and it is closed here
-- by dropping authenticated from the raw helpers.
--
-- That does not break the staff call chain. The rq_staff_* RPCs are themselves
-- SECURITY DEFINER, so when they call these helpers the effective role is the
-- function owner, who always retains EXECUTE. Revoking from anon and
-- authenticated only removes *direct* RPC access from PostgREST, which is
-- exactly what is wanted: staff go through the ownership-checked staff RPCs,
-- customers go through the token-scoped rq_public_* functions.

-- ------------------------------------------------- revoke the PUBLIC grant --
-- Discovered dynamically so it can never drift from the function set. The
-- updated_at trigger helper is excluded: it fires as the table owner on write
-- and is not an API entry point, so the default grant on it is harmless.
do $$
declare
  v_fn regprocedure;
begin
  for v_fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname like 'rq\_%'
      and p.proname <> 'rq_set_updated_at'
  loop
    execute format('revoke all on function %s from public', v_fn);
  end loop;
end;
$$;

-- ---------------------------------------------------- the public API only --
-- What an anonymous visitor is allowed to call. Every one of these is either
-- token-scoped (rq_public_lead/save/submit/quote/respond) or deliberately
-- coarse (rq_preview_quote returns headline totals only, never the breakdown).
grant execute on function public.rq_preview_quote(jsonb)                 to anon, authenticated;
grant execute on function public.rq_public_config()                      to anon, authenticated;
grant execute on function public.rq_public_start_lead(text, text)        to anon, authenticated;
grant execute on function public.rq_public_lead(text)                    to anon, authenticated;
grant execute on function public.rq_public_save(text, jsonb, integer, jsonb) to anon, authenticated;
grant execute on function public.rq_public_submit(text)                  to anon, authenticated;
grant execute on function public.rq_public_quote(text)                   to anon, authenticated;
grant execute on function public.rq_public_respond(text, text)           to anon, authenticated;

-- ---------------------------------------------------- staff-facing, session --
-- Staff RPCs and the full itemised preview. Each one calls rq_my_contractor_id()
-- internally and raises 42501 when there is no session, so ownership is
-- enforced on top of the grant.
grant execute on function public.rq_preview_quote_for_staff(jsonb)        to authenticated;
grant execute on function public.rq_staff_bootstrap()                     to authenticated;
grant execute on function public.rq_staff_save_settings(jsonb)            to authenticated;
grant execute on function public.rq_staff_save_rate_item(jsonb)           to authenticated;
grant execute on function public.rq_staff_delete_rate_item(uuid)          to authenticated;
grant execute on function public.rq_staff_reset_rate_items()              to authenticated;
grant execute on function public.rq_staff_save_question(jsonb)            to authenticated;
grant execute on function public.rq_staff_delete_question(uuid)           to authenticated;
grant execute on function public.rq_staff_reset_questions()               to authenticated;
grant execute on function public.rq_staff_list_leads(text, text, integer, integer)   to authenticated;
grant execute on function public.rq_staff_get_lead(uuid)                  to authenticated;
grant execute on function public.rq_staff_set_lead_status(uuid, text)     to authenticated;
grant execute on function public.rq_staff_list_quotes(text, text, integer, integer) to authenticated;
grant execute on function public.rq_staff_get_quote(uuid)                 to authenticated;
grant execute on function public.rq_staff_set_quote_status(uuid, text)    to authenticated;
grant execute on function public.rq_staff_save_quote_items(uuid, jsonb)   to authenticated;
grant execute on function public.rq_staff_save_quote_notes(uuid, text)    to authenticated;
grant execute on function public.rq_staff_regenerate_quote(uuid)          to authenticated;
grant execute on function public.rq_staff_save_ai(uuid, jsonb)            to authenticated;
grant execute on function public.rq_staff_log_event(uuid, text, text)     to authenticated;
grant execute on function public.rq_staff_dashboard_stats()               to authenticated;

-- ------------------------------- internal helpers: granted to nobody -------
-- 0003, 0004 and 0006 granted these to `anon, authenticated` outright, so
-- revoking from PUBLIC is not enough on its own: an explicit `authenticated`
-- grant has to be taken back as well. These stay reachable only from inside the
-- SECURITY DEFINER staff and public functions, which run as the owner, so the
-- staff call chain is unaffected while direct RPC access disappears.
--
-- Revoking the four commercial-data helpers is the actual point of this section.
-- They are SECURITY DEFINER, accept an arbitrary contractor uuid and carry no
-- internal auth check, so while `authenticated` held EXECUTE any logged-in user
-- could read another tenant's rate card via rq_effective_rate_items /
-- rq_rate_lookup, or recompute their quote via rq_compute_quote.
revoke all on function public.rq_effective_rate_items(uuid)   from anon, authenticated;
revoke all on function public.rq_rate_lookup(uuid, text)      from anon, authenticated;
revoke all on function public.rq_effective_questions(uuid)   from anon, authenticated;
revoke all on function public.rq_coerce_answers(uuid, jsonb)  from anon, authenticated;
revoke all on function public.rq_compute_quote(uuid, jsonb)  from anon, authenticated;
revoke all on function public.rq_create_quote(uuid)           from anon, authenticated;
revoke all on function public.rq_default_contractor_id()      from anon, authenticated;
revoke all on function public.rq_new_token()                  from anon, authenticated;
revoke all on function public.rq_ensure_contractor()          from anon, authenticated;
revoke all on function public.rq_my_contractor_id()           from anon, authenticated;
revoke all on function public.rq_on_auth_user_created()       from anon, authenticated;
revoke all on function public.rq_apply_totals(jsonb, jsonb, numeric) from anon, authenticated;
revoke all on function public.rq_add_item(jsonb, text, text, text, text, numeric, text, numeric) from anon, authenticated;
revoke all on function public.rq_add_warning(jsonb, text)     from anon, authenticated;
revoke all on function public.rq_bool(jsonb, text, boolean)   from anon, authenticated;
revoke all on function public.rq_num(jsonb, text, numeric)    from anon, authenticated;
revoke all on function public.rq_txt(jsonb, text, text)       from anon, authenticated;
revoke all on function public.rq_like(text)                   from anon, authenticated;

-- ------------------------------- policy helpers: must stay callable --------
-- rq_is_admin and rq_owns_row are referenced by 10 RLS policies on
-- rq_contractors, rq_leads, rq_questions, rq_quotes, rq_rate_items,
-- rq_quote_events and rq_quote_items. RLS policy expressions are evaluated as
-- the querying role, so revoking EXECUTE from authenticated does not just hide
-- these helpers, it breaks every direct table read and write for a logged-in
-- user with "permission denied for function rq_is_admin".
--
-- They are safe to expose because they return a single boolean authorisation
-- verdict rather than any commercial data, and they are already gated on
-- auth.uid() by the policy itself. anon is dropped, since only a session can
-- satisfy an ownership check.
revoke all on function public.rq_is_admin()   from anon;
revoke all on function public.rq_owns_row(uuid) from anon;
grant execute on function public.rq_is_admin()    to authenticated;
grant execute on function public.rq_owns_row(uuid) to authenticated;
