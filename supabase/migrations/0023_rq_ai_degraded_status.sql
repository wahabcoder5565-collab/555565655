-- Roofing Quote Generator :: let a failed LLM call be seen as a failure
--
-- rq_staff_save_ai always set ai_status = 'ready', whether the prose came from
-- the LLM or from the deterministic fallback in engine.ts. So when Gemini was
-- misconfigured, rate limited or out of capacity, the contractor saw "ready"
-- next to clearly rule-generated text and had no way to tell the two apart.
--
-- The extra payload keys are optional, so existing callers keep working: a
-- payload without llm_ok still records 'ready'.
--
-- ai_status is widened to cover the two outcomes that are genuinely useful to
-- see: degraded (a provider was configured but the prose came from the rules
-- engine) and failed (the provider was tried and nothing usable came back).

alter table public.rq_quotes
  drop constraint if exists rq_quotes_ai_status_check;

alter table public.rq_quotes
  add constraint rq_quotes_ai_status_check
  check (ai_status in ('pending', 'ready', 'degraded', 'failed'));

create or replace function public.rq_staff_save_ai(
  p_quote_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_cid uuid;
  v_ok boolean;
  v_status text;
begin
  v_cid := public.rq_my_contractor_id();
  if v_cid is null then
    raise exception 'Not authorised' using errcode = '42501';
  end if;

  -- Default to ready so a caller that does not send llm_ok behaves as before.
  v_ok := coalesce((p_payload ->> 'llm_ok')::boolean, true);
  v_status := case when v_ok then 'ready' else 'degraded' end;

  update public.rq_quotes q
  set ai_scope_of_work = left(coalesce(public.rq_txt(p_payload, 'scope_of_work', ''), ''), 12000),
      ai_summary = left(coalesce(public.rq_txt(p_payload, 'summary', ''), ''), 2000),
      ai_recommendations = coalesce(p_payload -> 'recommendations', '[]'::jsonb),
      ai_risk_notes = coalesce(p_payload -> 'risk_notes', '[]'::jsonb),
      ai_engine = left(coalesce(public.rq_txt(p_payload, 'engine', 'rules'), 'rules'), 40),
      ai_model = nullif(left(coalesce(public.rq_txt(p_payload, 'model', ''), ''), 120), ''),
      ai_status = v_status,
      ai_error = case
        when v_ok then null
        else left(coalesce(
          nullif(public.rq_txt(p_payload, 'error', ''), ''),
          'The language model was unavailable, so the rules engine wrote this scope instead. Every price is unaffected.'
        ), 2000)
      end,
      ai_generated_at = now()
  where q.id = p_quote_id and q.contractor_id = v_cid;

  if not found then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  insert into public.rq_quote_events (quote_id, lead_id, actor_id, actor_role, action, detail)
  select q.id, q.lead_id, auth.uid(), 'system',
    case when v_ok then 'ai_generated' else 'ai_degraded' end,
    'Scope of work written by ' || q.ai_engine
  from public.rq_quotes q where q.id = p_quote_id;

  return jsonb_build_object('ok', v_ok, 'status', v_status);
end;
$$;

revoke all on function public.rq_staff_save_ai(uuid, jsonb) from public;
grant execute on function public.rq_staff_save_ai(uuid, jsonb) to authenticated;