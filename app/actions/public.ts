"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import {
  respondToQuote,
  saveLead,
  startLead,
  submitLead,
} from "@/lib/rq/public";
import type { ActionState } from "@/lib/rq/action-state";
import type { Answers, Contact, SubmitResult } from "@/lib/rq/types";

export type { ActionState };

/** Creates the lead and sends the customer into the wizard at its token URL. */
export async function startQuoteAction(
  _prev: ActionState,
  _formData: FormData,
): Promise<ActionState> {
  let token: string;
  try {
    ({ token } = await startLead("web", ""));
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Could not start a quote.",
    };
  }
  // redirect() signals control flow by throwing, so it must stay outside the
  // try/catch above.
  redirect(`/q/${token}`);
}

export async function saveAnswersAction(
  token: string,
  answers: Answers,
  step: number,
  contact: Contact,
): Promise<SaveResultShape> {
  try {
    const res = await saveLead(token, answers, step, contact);
    return {
      ok: true,
      message: "Saved",
      answered: res.answered,
      completion: res.completion,
      activeQuestions: res.active_questions,
    };
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Could not save your answers.",
      answered: 0,
      completion: 0,
      activeQuestions: 0,
    };
  }
}

export type SaveResultShape = {
  ok: boolean;
  message: string;
  answered: number;
  completion: number;
  activeQuestions: number;
};

export async function submitQuoteAction(token: string): Promise<ActionState> {
  let res: SubmitResult;
  try {
    res = await submitLead(token);
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Could not submit your answers.",
    };
  }

  // A missing-required-field result is a normal outcome, not an exception.
  if (!res.ok) {
    return {
      ok: false,
      message: res.error ?? "Please answer the required questions.",
      missing: res.missing ?? [],
    };
  }

  if (!res.quote_token) {
    return { ok: false, message: "The quote was created but no link was returned." };
  }

  // redirect() signals control flow by throwing, so it must be the last thing.
  redirect(`/quote/${res.quote_token}`);
}

export async function respondAction(
  quoteToken: string,
  decision: "accepted" | "declined",
): Promise<ActionState> {
  try {
    const res = await respondToQuote(quoteToken, decision);
    // The page reads the quote through a volatile RPC, so it has to be
    // revalidated for the new status to render.
    revalidatePath(`/quote/${quoteToken}`);
    return { ok: true, message: `Quote ${res.status}.` };
  } catch (err) {
    return {
      ok: false,
      message: err instanceof Error ? err.message : "Could not record your decision.",
    };
  }
}

export async function refreshStaff(): Promise<void> {
  revalidatePath("/staff", "layout");
}