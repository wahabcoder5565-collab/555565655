"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import { requireSupabaseEnv } from "@/lib/env";

export type GenerateScopeState = { error: string | null };

/**
 * Invokes the rq-generate-quote Edge Function with the caller's own session
 * token. The function re-resolves the caller and does its reads and writes
 * through the rq_staff_* RPCs, so this server action cannot widen access even
 * though it forwards a quote id from the client.
 */
export async function generateScopeAction(
  _prev: GenerateScopeState,
  formData: FormData,
): Promise<GenerateScopeState> {
  const quoteId = String(formData.get("quoteId") ?? "");
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(quoteId)) {
    return { error: "That quote id is not valid." };
  }

  const supabase = await createClient();
  const { data: sessionData } = await supabase.auth.getSession();
  const token = sessionData.session?.access_token;

  if (!token) {
    return { error: "Your session expired. Sign in again and retry." };
  }

  const { url, key } = requireSupabaseEnv();

  let res: Response;
  try {
    res = await fetch(`${url}/functions/v1/rq-generate-quote`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        apikey: key,
        "content-type": "application/json",
      },
      body: JSON.stringify({ quoteId }),
    });
  } catch (err) {
    console.error("generateScope: fetch failed", err);
    return { error: "Could not reach the scope generator. Try again shortly." };
  }

  if (!res.ok) {
    const body = (await res.json().catch(() => null)) as { error?: string } | null;
    return { error: body?.error ?? `Generator failed (${res.status}).` };
  }

  // The function writes the prose through rq_staff_save_ai; revalidation makes
  // the server component re-read the quote so the new prose is shown.
  revalidatePath(`/staff/quotes/${quoteId}`);
  return { error: null };
}