import { createClient } from "@/lib/supabase/server";
import { callRpc as call } from "@/lib/rq/transport";
import type {
  Answers,
  Contact,
  PublicConfig,
  PublicLead,
  PublicPreview,
  PublicQuote,
  RespondResult,
  SaveResult,
  StartLeadResult,
  SubmitResult,
} from "@/lib/rq/types";

/**
 * Public RPCs. PostgREST reports failures in the response body rather than as
 * transport errors, so `error` is checked explicitly on every call and turned
 * into a thrown Error with the server's message.
 *
 * callRpc retries transient transport failures; see lib/rq/transport.ts.
 */
export async function getPublicConfig(): Promise<PublicConfig> {
  const supabase = await createClient();
  return call<PublicConfig>(
    () => supabase.rpc("rq_public_config" as never, {} as never),
    "rq_public_config",
  );
}

export async function startLead(source = "", campaign = ""): Promise<StartLeadResult> {
  const supabase = await createClient();
  return call<StartLeadResult>(
    () => supabase.rpc("rq_public_start_lead" as never, { p_source: source, p_campaign: campaign } as never),
    "rq_public_start_lead",
  );
}

export async function getLead(token: string): Promise<PublicLead> {
  const supabase = await createClient();
  return call<PublicLead>(
    () => supabase.rpc("rq_public_lead" as never, { p_token: token } as never),
    "rq_public_lead",
  );
}

export async function saveLead(
  token: string,
  answers: Answers,
  step: number,
  contact: Contact,
): Promise<SaveResult> {
  const supabase = await createClient();
  return call<SaveResult>(
    () =>
      supabase.rpc("rq_public_save" as never, {
        p_token: token,
        p_answers: answers,
        p_step: step,
        p_contact: contact,
      } as never),
    "rq_public_save",
  );
}

export async function submitLead(token: string): Promise<SubmitResult> {
  const supabase = await createClient();
  return call<SubmitResult>(
    () => supabase.rpc("rq_public_submit" as never, { p_token: token } as never),
    "rq_public_submit",
  );
}

export async function getPublicQuote(quoteToken: string): Promise<PublicQuote> {
  const supabase = await createClient();
  return call<PublicQuote>(
    () => supabase.rpc("rq_public_quote" as never, { p_token: quoteToken } as never),
    "rq_public_quote",
  );
}

export async function respondToQuote(
  quoteToken: string,
  decision: "accepted" | "declined",
): Promise<RespondResult> {
  const supabase = await createClient();
  return call<RespondResult>(
    () =>
      supabase.rpc("rq_public_respond" as never, {
        p_token: quoteToken,
        p_decision: decision,
      } as never),
    "rq_public_respond",
  );
}

/**
 * Anonymous coarse preview. Returns null when no contractor exists yet, which is
 * the expected state before the first staff signup.
 */
export async function previewQuote(answers: Answers): Promise<PublicPreview | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("rq_preview_quote" as never, {
    p_answers: answers,
  } as never);
  if (error) throw new Error(`rq_preview_quote failed: ${error.message}`);
  return (data as PublicPreview | null) ?? null;
}