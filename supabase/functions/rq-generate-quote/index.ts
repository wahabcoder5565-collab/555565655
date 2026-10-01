/**
 * rq-generate-quote
 *
 * Writes the scope-of-work prose for one quote.
 *
 * Contract:
 *   POST  { "quoteId": "<uuid>" }
 *   Auth: a staff session (Authorization: Bearer <access token>). verify_jwt is
 *   on, and the handler additionally resolves the caller with auth.getUser and
 *   relies on rq_staff_* RPCs to scope every read and write to that
 *   contractor. There is no path from this function to another contractor's
 *   data.
 *
 * The prose is advisory. It cannot change a price: the totals it is written
 * around are read from the quote and never recomputed here.
 */

import { createClient } from "@supabase/supabase-js@2";
import { buildDeterministicDraft, type QuoteInput } from "./engine.ts";
import { activeModel, draftWithLlm, resolveProvider } from "./llm.ts";

const cors: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "content-type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "Use POST." }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) {
    return json({ ok: false, error: "Function is not configured." }, 500);
  }

  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) {
    return json({ ok: false, error: "Missing session token." }, 401);
  }

  // The caller's own token is used for every client, so the definer chain in
  // Postgres resolves ownership from it. No service role key is involved.
  const supabase = createClient(url, anonKey, {
    global: { headers: { authorization: `Bearer ${token}` } },
    auth: { persistSession: false },
  });

  const { data: userData, error: userErr } = await supabase.auth.getUser(token);
  if (userErr || !userData.user) {
    return json({ ok: false, error: "Invalid or expired session." }, 401);
  }

  let body: { quoteId?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "Body must be JSON." }, 400);
  }

  const quoteId = typeof body.quoteId === "string" ? body.quoteId : "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(quoteId)) {
    return json({ ok: false, error: "quoteId must be a uuid." }, 400);
  }

  const { data: detail, error: readErr } = await supabase.rpc("rq_staff_get_quote", {
    p_quote_id: quoteId,
  });

  if (readErr) {
    // "Quote not found" is the same answer for someone else's quote and a
    // deleted one, which is what we want.
    const status = readErr.message.toLowerCase().includes("not found") ? 404 : 400;
    return json({ ok: false, error: readErr.message }, status);
  }
  if (!detail) {
    return json({ ok: false, error: "Quote not found." }, 404);
  }

  // Reported up front so a caller can tell "no provider configured" apart from
  // "the provider was tried and failed".
  const provider = resolveProvider();

  const quote = (detail.quote ?? {}) as Record<string, unknown>;
  const lead = (detail.lead ?? {}) as Record<string, unknown>;
  const contractor = (detail.contractor ?? {}) as Record<string, unknown>;
  const items = (detail.items ?? []) as QuoteInput["items"];

  const input: QuoteInput = {
    quoteNumber: String(quote.quote_number ?? ""),
    projectType: String(quote.project_type ?? "roofing"),
    roofAreaSqft: Number(quote.roof_area_sqft ?? 0),
    // Neither warranty_years nor currency is a column on rq_quotes; both live on
    // rq_contractors, which rq_staff_get_quote now returns.
    warrantyYears: Number(contractor.warranty_years ?? 0),
    answers: (quote.answers ?? lead.answers ?? {}) as Record<string, unknown>,
    items,
    total: Number(quote.total ?? 0),
    depositAmount: Number(quote.deposit_amount ?? 0),
    currency: String(contractor.currency ?? "USD"),
    validUntil: quote.valid_until ? String(quote.valid_until) : "",
    warnings: Array.isArray(quote.warnings) ? (quote.warnings as string[]) : null,
  };

  // The deterministic draft always runs and is the floor.
  const baseline = buildDeterministicDraft(input);

  let draft = baseline;
  let engine = "rules";
  let model: string | null = null;

  if (provider) {
    const improved = await draftWithLlm(input);
    if (improved) {
      // Fields absent from the LLM response fall back to the deterministic
      // text rather than becoming blank.
      draft = {
        scope_of_work: improved.scope_of_work ?? baseline.scope_of_work,
        summary: improved.summary ?? baseline.summary,
        recommendations: improved.recommendations ?? baseline.recommendations,
        risk_notes: improved.risk_notes ?? baseline.risk_notes,
      };
      engine = provider;
      model = activeModel();
    }
  }

  const { error: saveErr } = await supabase.rpc("rq_staff_save_ai", {
    p_quote_id: quoteId,
    p_payload: {
      scope_of_work: draft.scope_of_work,
summary: draft.summary,
    recommendations: draft.recommendations,
    risk_notes: draft.risk_notes,
    engine,
    model: model ?? "",
    provider: provider ?? "none",
    // Lets the caller distinguish an unconfigured provider from a failed one.
    llm_ok: engine !== "rules",
    },
  });

  if (saveErr) {
    return json({ ok: false, error: saveErr.message }, 400);
  }

  return json({
    ok: true,
    quoteId,
    engine,
    scope_of_work: draft.scope_of_work,
    summary: draft.summary,
    recommendations: draft.recommendations,
    risk_notes: draft.risk_notes,
    // Echoed so the caller can see the numbers the prose was written around
    // came from the database and were not altered here.
    total: input.total,
    deposit_amount: input.depositAmount,
  });
});