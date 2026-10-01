-- Roofing Quote Generator :: defence in depth on the anon grant
--
-- 0013 closed the data leak, and the audit confirmed every rq_staff_* function
-- already refuses an anonymous caller internally (42501). But relying on an
-- internal check is the weaker pattern: if a future edit drops or reorders that
-- guard, the function is immediately world-callable with no compiler or
-- linter complaint. The Supabase security advisor flags exactly this shape as
-- anon_security_definer_function_executable.
--
-- So the anon grant is removed from every staff and internal function. The
-- internal guards are deliberately kept: the staff RPCs are SECURITY DEFINER
-- and call rq_my_contractor_id(), so the check has to exist regardless, and it
-- is what enforces ownership between contractors on a shared project.
--
-- Net result: the public surface is exactly the seven rq_public_* functions
-- plus rq_preview_quote, and nothing else is reachable without a session.

-- Staff RPCs: authenticated only, enforced at the grant as well as internally.
revoke all on function public.rq_staff_bootstrap() from anon;
revoke all on function public.rq_staff_save_settings(jsonb) from anon;
revoke all on function public.rq_staff_save_rate_item(jsonb) from anon;
revoke all on function public.rq_staff_delete_rate_item(uuid) from anon;
revoke all on function public.rq_staff_reset_rate_items() from anon;
revoke all on function public.rq_staff_save_question(jsonb) from anon;
revoke all on function public.rq_staff_delete_question(uuid) from anon;
revoke all on function public.rq_staff_reset_questions() from anon;
revoke all on function public.rq_staff_list_leads(text, text, integer, integer) from anon;
revoke all on function public.rq_staff_get_lead(uuid) from anon;
revoke all on function public.rq_staff_set_lead_status(uuid, text) from anon;
revoke all on function public.rq_staff_list_quotes(text, text, integer, integer) from anon;
revoke all on function public.rq_staff_get_quote(uuid) from anon;
revoke all on function public.rq_staff_set_quote_status(uuid, text) from anon;
revoke all on function public.rq_staff_save_quote_items(uuid, jsonb) from anon;
revoke all on function public.rq_staff_save_quote_notes(uuid, text) from anon;
revoke all on function public.rq_staff_regenerate_quote(uuid) from anon;
revoke all on function public.rq_staff_save_ai(uuid, jsonb) from anon;
revoke all on function public.rq_staff_log_event(uuid, text, text) from anon;
revoke all on function public.rq_staff_dashboard_stats() from anon;
revoke all on function public.rq_preview_quote_for_staff(jsonb) from anon;

-- Internal identity, pricing and coercion helpers.
revoke all on function public.rq_effective_rate_items(uuid) from anon;
revoke all on function public.rq_rate_lookup(uuid, text) from anon;
revoke all on function public.rq_effective_questions(uuid) from anon;
revoke all on function public.rq_coerce_answers(uuid, jsonb) from anon;
revoke all on function public.rq_compute_quote(uuid, jsonb) from anon;
revoke all on function public.rq_create_quote(uuid) from anon;
revoke all on function public.rq_ensure_contractor() from anon;
revoke all on function public.rq_default_contractor_id() from anon;
revoke all on function public.rq_my_contractor_id() from anon;
revoke all on function public.rq_new_token() from anon;
revoke all on function public.rq_is_admin() from anon;
revoke all on function public.rq_owns_row(uuid) from anon;
revoke all on function public.rq_on_auth_user_created() from anon;
revoke all on function public.rq_apply_totals(jsonb, jsonb, numeric) from anon, authenticated;

-- Pure jsonb helpers. Not SECURITY DEFINER, so they cannot escalate, but they
-- are implementation detail rather than API and have no anon caller.
revoke all on function public.rq_add_item(jsonb, text, text, text, text, numeric, text, numeric) from anon;
revoke all on function public.rq_add_warning(jsonb, text) from anon;
revoke all on function public.rq_bool(jsonb, text, boolean) from anon;
revoke all on function public.rq_num(jsonb, text, numeric) from anon;
revoke all on function public.rq_txt(jsonb, text, text) from anon;
revoke all on function public.rq_like(text) from anon;
