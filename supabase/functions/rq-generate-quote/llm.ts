/**
 * Optional LLM prose pass.
 *
 * Two providers are supported. Gemini is preferred when GEMINI_API_KEY is set,
 * otherwise the OpenAI-compatible path is used if RQ_LLM_API_KEY is set. With
 * neither, llmConfigured() is false and the deterministic draft in engine.ts
 * stands on its own. The LLM is never required.
 *
 * The LLM is given the priced line items and the customer's answers and asked to
 * write better English around them. It is explicitly instructed not to produce
 * any figure, and its output is filtered by sanitise() regardless: only the four
 * prose fields are read out of its response. Every number on the quote comes from
 * Postgres via engine.ts, so a hallucinated price cannot reach the customer.
 */

import type { Draft, QuoteInput } from "./engine.ts";

const PROVIDER = (Deno.env.get("RQ_LLM_PROVIDER") ?? "").trim().toLowerCase();
const GEMINI_API_KEY = (Deno.env.get("GEMINI_API_KEY") ?? "").trim();
const OPENAI_API_KEY = (Deno.env.get("RQ_LLM_API_KEY") ?? "").trim();

const GEMINI_MODEL = Deno.env.get("RQ_GEMINI_MODEL") ?? "gemini-3.6-flash";
const OPENAI_MODEL = Deno.env.get("RQ_LLM_MODEL") ?? "gpt-4o-mini";
const OPENAI_BASE_URL = (
  Deno.env.get("RQ_LLM_BASE_URL") ?? "https://api.openai.com/v1"
).replace(/\/$/, "");

const TIMEOUT_MS = 25_000;
const GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models";

/** How many times to retry a provider that is temporarily unavailable. */
const ATTEMPTS = 4;

/**
 * Gemini's free tier returns 429/503 under load and asks callers to retry.
 * These are transient by definition, so they are worth several tries. 400 and 401
 * are not: a bad key or a malformed request will never succeed on a retry, and
 * retrying only delays the deterministic fallback.
 */
function isRetryableStatus(status: number): boolean {
  return status === 429 || status === 500 || status === 502 || status === 503 || status === 504;
}

export type ResolvedProvider = "gemini" | "openai";

export function resolveProvider(): ResolvedProvider | null {
  // An explicit provider setting wins, but only if that provider has a key.
  if (PROVIDER === "gemini" && GEMINI_API_KEY) return "gemini";
  if (PROVIDER === "openai" && OPENAI_API_KEY) return "openai";
  if (GEMINI_API_KEY) return "gemini";
  if (OPENAI_API_KEY) return "openai";
  return null;
}

export function llmConfigured(): boolean {
  return resolveProvider() !== null;
}

export function activeModel(): string | null {
  const provider = resolveProvider();
  if (provider === "gemini") return GEMINI_MODEL;
  if (provider === "openai") return OPENAI_MODEL;
  return null;
}

const SYSTEM = `You write roofing scope-of-work prose for a contractor's customer quote.

Hard rules:
- Never state, restate, recompute, or adjust any price, quantity, total, deposit, percentage or date. They are already correct and printed separately. Refer to them only as "the total shown above" if you must refer to them at all.
- Do not add line items, remove line items, or promise work that is not in the provided list.
- Do not invent building codes, permits, or warranty terms.
- Plain professional English. No emoji, no markdown headers, no bullet characters other than "- ".

Return ONLY a JSON object with exactly these keys:
  "scope_of_work": string  (the customer-facing scope, 3-8 short paragraphs or a sectioned list)
  "summary": string        (one sentence)
  "recommendations": string[] (2-4 practical next steps for the customer)
  "risk_notes": string[]      (2-4 honest caveats)`;

function buildUserPrompt(input: QuoteInput): string {
  const lines = input.items
    .map((i) => {
      const qty = Number(i.quantity).toLocaleString();
      return `- ${i.label}${i.description ? ` (${i.description})` : ""}: ${qty} ${i.unit}`;
    })
    .join("\n");

  const answers = Object.entries(input.answers)
    .filter(([, v]) => v !== null && v !== undefined && v !== "")
    .map(([k, v]) => `- ${k}: ${Array.isArray(v) ? v.join(", ") : String(v)}`)
    .join("\n");

  // Note the absence of any currency figure. The line items are named so the
  // model can describe the work, but no number reaches the prompt at all. That
  // makes the "never state a figure" rule easy for the model to keep rather than
  // relying on it to resist copying figures it was shown.
  return `Project type: ${input.projectType}
Roof area: ${Number(input.roofAreaSqft).toLocaleString()} sq ft
Warranty: ${input.warrantyYears} years

Customer's own answers (may include their spelling, use it to understand intent):
${answers || "- none"}

Work included on this quote (named only, no figures are provided or needed):
${lines || "- none"}

Write the scope of work. Do not mention any figure.`;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Issues one request per attempt, retrying only statuses that can succeed on a
 * later try. Returns the parsed response body, or null when the provider cannot
 * be used, in which case the deterministic draft stands.
 */
async function requestWithRetry(
  buildRequest: () => { url: string; init: RequestInit },
  label: string,
): Promise<unknown | null> {
  for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
    const { url, init } = buildRequest();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

    try {
      const res = await fetch(url, { ...init, signal: controller.signal });

      if (res.ok) return await res.json();

      const detail = await res.text().catch(() => "");
      if (isRetryableStatus(res.status) && attempt < ATTEMPTS) {
        const wait = attempt * 700;
        console.warn(
          `${label}: http ${res.status} (${res.status === 429 ? "rate limited" : "unavailable"}), ` +
            `retrying in ${wait}ms (attempt ${attempt}/${ATTEMPTS})`,
        );
        await sleep(wait);
        continue;
      }

      console.warn(`${label}: http ${res.status}${detail ? ` ${detail.slice(0, 200)}` : ""}`);
      return null;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      if (attempt < ATTEMPTS) {
        console.warn(`${label}: ${message}, retrying (attempt ${attempt}/${ATTEMPTS})`);
        await sleep(attempt * 700);
        continue;
      }
      console.warn(`${label}: failed after ${ATTEMPTS} attempts: ${message}`);
      return null;
    } finally {
      clearTimeout(timer);
    }
  }
  return null;
}

async function draftWithGemini(input: QuoteInput): Promise<Partial<Draft> | null> {
  const body = {
    systemInstruction: { parts: [{ text: SYSTEM }] },
    contents: [{ role: "user", parts: [{ text: buildUserPrompt(input) }] }],
    generationConfig: {
      temperature: 0.2,
      maxOutputTokens: 1200,
      responseMimeType: "application/json",
    },
  };

  const data = await requestWithRetry(
    () => ({
      url: `${GEMINI_BASE}/${GEMINI_MODEL}:generateContent`,
      init: {
        method: "POST",
        headers: { "content-type": "application/json", "x-goog-api-key": GEMINI_API_KEY },
        body: JSON.stringify(body),
      },
    }),
    "llm:gemini",
  );

  const candidates = (data as { candidates?: unknown[] } | null)?.candidates;
  const first = Array.isArray(candidates) ? candidates[0] : null;
  if (!first || typeof first !== "object") return null;

  const parts = (first as { content?: { parts?: unknown[] } }).content?.parts;
  if (!Array.isArray(parts) || parts.length === 0) return null;

  const text = (parts[0] as { text?: unknown }).text;
  if (typeof text !== "string" || !text.trim()) return null;

  // responseMimeType should make this a bare object, but models can still wrap
  // JSON in a fence or prose, so unwrap before parsing.
  return sanitise(parseJsonLoose(text));
}

async function draftWithOpenAi(input: QuoteInput): Promise<Partial<Draft> | null> {
  const body = {
    model: OPENAI_MODEL,
    temperature: 0.2,
    max_tokens: 1200,
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: SYSTEM },
      { role: "user", content: buildUserPrompt(input) },
    ],
  };

  const data = await requestWithRetry(
    () => ({
      url: `${OPENAI_BASE_URL}/chat/completions`,
      init: {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${OPENAI_API_KEY}`,
        },
        body: JSON.stringify(body),
      },
    }),
    "llm:openai",
  );

  const choices = (data as { choices?: unknown[] } | null)?.choices;
  const content = Array.isArray(choices)
    ? (choices[0] as { message?: { content?: unknown } } | undefined)?.message?.content
    : undefined;

  if (typeof content !== "string" || !content.trim()) return null;
  return sanitise(parseJsonLoose(content));
}

/** Parses JSON that may be fenced or surrounded by stray text. */
function parseJsonLoose(raw: string): unknown {
  const trimmed = raw.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
    if (fenced?.[1]) {
      try {
        return JSON.parse(fenced[1].trim());
      } catch {
        return null;
      }
    }
    const first = trimmed.indexOf("{");
    const last = trimmed.lastIndexOf("}");
    if (first !== -1 && last > first) {
      try {
        return JSON.parse(trimmed.slice(first, last + 1));
      } catch {
        return null;
      }
    }
    return null;
  }
}

/**
 * Returns a partial Draft containing only the prose fields, or null if the
 * provider is unconfigured, errors, times out, or returns something unusable.
 * A null here is normal and simply means the deterministic draft stands.
 */
export async function draftWithLlm(input: QuoteInput): Promise<Partial<Draft> | null> {
  const provider = resolveProvider();
  if (provider === "gemini") return draftWithGemini(input);
  if (provider === "openai") return draftWithOpenAi(input);
  return null;
}

const MAX_LEN = 12_000;

function str(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const trimmed = v.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, max);
}

function strArray(v: unknown, max: number): string[] {
  if (!Array.isArray(v)) return [];
  return v
    .map((x) => str(x, 400))
    .filter((x): x is string => x !== null)
    .slice(0, max);
}

/**
 * Only the four prose keys survive. Any extra key the model invented, including
 * anything numeric, is discarded here rather than trusted.
 *
 * The prompt also asks the model to avoid figures, but that is an instruction and
 * not a guarantee, so any currency-looking amount in the prose is stripped. A
 * scope that survives this is still advisory text; the totals shown to the
 * customer come from Postgres.
 */
const FIGURE_RE = /(?:[$€£]\s?\d[\d,]*(?:\.\d{2})?|\b\d[\d,]*\.\d{2}\b)/g;

function stripFigures(v: string): string {
  const cleaned = v.replace(FIGURE_RE, "").replace(/[ \t]{2,}/g, " ").trim();
  return cleaned;
}

/**
 * Only the four prose keys survive. Any extra key the model invented, including
 * anything numeric, is discarded here rather than trusted.
 */
function sanitise(raw: unknown): Partial<Draft> | null {
  if (typeof raw !== "object" || raw === null) return null;
  const o = raw as Record<string, unknown>;

  const out: Partial<Draft> = {};

  const scope = str(o.scope_of_work, MAX_LEN);
  if (scope) {
    const cleaned = stripFigures(scope);
    if (cleaned.length > 40) out.scope_of_work = cleaned;
  }

  const summary = str(o.summary, 500);
  if (summary) {
    const cleaned = stripFigures(summary);
    if (cleaned) out.summary = cleaned;
  }

  const recs = strArray(o.recommendations, 5)
    .map(stripFigures)
    .filter((s) => s.length > 5);
  if (recs.length) out.recommendations = recs;

  const risks = strArray(o.risk_notes, 5)
    .map(stripFigures)
    .filter((s) => s.length > 5);
  if (risks.length) out.risk_notes = risks;

  return Object.keys(out).length > 0 ? out : null;
}