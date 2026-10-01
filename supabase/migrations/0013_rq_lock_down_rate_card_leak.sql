-- Roofing Quote Generator :: close the rate card leak to anonymous callers
--
-- A security audit showed the staff RPCs correctly refuse anonymous callers
-- (each one raises 42501 internally), but the helpers they are built on were
-- still granted EXECUTE to anon and have no internal auth check of their own:
--
--   rq_effective_rate_items(uuid)  -- dumps every unit_price on the rate card
--   rq_rate_lookup(uuid, text)     -- dumps any single price by code
--   rq_effective_questions(uuid)   -- dumps the questionnaire
--   rq_coerce_answers(uuid, jsonb) -- dumps the answer schema
--   rq_default_contractor_id()     -- discloses the contractor uuid
--   rq_my_contractor_id()          -- internal identity helper
--   rq_new_token()                 -- internal token generator
--   rq_is_admin(), rq_owns_row()   -- internal authorisation helpers
--   rq_on_auth_user_created()      -- trigger function, not for RPC use
--
-- rq_compute_quote was granted to anon in 0004 and is the most damaging of all:
-- it returns a fully itemised quote for the default contractor, including every
-- unit price, markup percentage and the contractor's overhead and profit
-- figures. Anyone could call it anonymously and reconstruct the entire business.
--
-- The public wizard does need *some* anon pricing, so rq_preview_quote is kept
-- but rewritten to return only a coarse range: no unit prices, no per-line
-- breakdown, and no pricing knobs. The customer sees a ballpark while filling
-- in the form; the itemised quote is only revealed after they submit, through
-- rq_public_quote, which is scoped to their own token.

-- ---------------------------------------------------------------- pricing --

create or replace function public.rq_preview_quote(p_answers jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_full jsonb;
begin
  v_cid := public.rq_default_contractor_id();
  if v_cid is null then
    return null;
  end if;

  v_full := public.rq_compute_quote(v_cid, p_answers);

  -- Only the headline numbers a customer is entitled to while deciding whether
  -- to continue. The itemised breakdown and the pricing knobs stay behind the
  -- submitted-quote boundary.
  return jsonb_build_object(
    'roof_area_sqft', v_full #> '{inputs,roof_area_sqft}',
    'area_source', v_full #> '{inputs,area_source}',
    'estimated_total', v_full #> '{totals,total}',
    'deposit_amount', v_full #> '{totals,deposit_amount}',
    'price_per_sqft', v_full #> '{totals,price_per_sqft}',
    'currency', v_full #> '{pricing,currency}',
    'is_placeholder', (v_full #> '{inputs,roof_area_sqft}')::numeric = 0
  );
end;
$$;

-- Staff keep the full engine.
create or replace function public.rq_preview_quote_for_staff(p_answers jsonb)
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
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  return public.rq_compute_quote(v_cid, p_answers);
end;
$$;

revoke all on function public.rq_preview_quote(jsonb) from public;
revoke all on function public.rq_preview_quote_for_staff(jsonb) from public;
grant execute on function public.rq_preview_quote(jsonb) to anon, authenticated;
grant execute on function public.rq_preview_quote_for_staff(jsonb) to authenticated;

-- ------------------------------------------- anon loses internal helpers --

revoke all on function public.rq_effective_rate_items(uuid) from anon;
revoke all on function public.rq_rate_lookup(uuid, text) from anon;
revoke all on function public.rq_effective_questions(uuid) from anon;
revoke all on function public.rq_coerce_answers(uuid, jsonb) from anon;
revoke all on function public.rq_default_contractor_id() from anon;
revoke all on function public.rq_my_contractor_id() from anon;
revoke all on function public.rq_new_token() from anon;
revoke all on function public.rq_is_admin() from anon;
revoke all on function public.rq_owns_row(uuid) from anon;
revoke all on function public.rq_compute_quote(uuid, jsonb) from anon;
revoke all on function public.rq_create_quote(uuid) from anon;
revoke all on function public.rq_ensure_contractor() from anon;
revoke all on function public.rq_on_auth_user_created() from anon;

-- These are plain data helpers with no auth check, so they were never meant to
-- be directly callable by anyone. They stay available to authenticated callers
-- only for the staff RPCs, which is where they are actually used.
revoke all on function public.rq_add_item(jsonb, text, text, text, text, numeric, text, numeric) from anon, authenticated;
revoke all on function public.rq_add_warning(jsonb, text) from anon, authenticated;
revoke all on function public.rq_apply_totals(jsonb, jsonb, numeric) from anon, authenticated;
revoke all on function public.rq_bool(jsonb, text, boolean) from anon, authenticated;
revoke all on function public.rq_num(jsonb, text, numeric) from anon, authenticated;
revoke all on function public.rq_txt(jsonb, text, text) from anon, authenticated;
revoke all on function public.rq_like(text) from anon, authenticated;

-- ------------------------------------------------------------------ RLS ----
-- rq_preview_quote no longer returns rows from rq_questions, but the functions
-- it calls still run as their owner. RLS is on those tables and the engine is
-- SECURITY DEFINER, so the existing policies already allow the default
-- contractor's system rows; nothing to relax here.

-- The probe function was only for this audit.
drop function if exists public.rq_probe_anonymous_calls();
