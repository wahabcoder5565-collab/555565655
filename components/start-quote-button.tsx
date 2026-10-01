"use client";

import { useActionState } from "react";
import { startQuoteAction } from "@/app/actions/public";
import { PUBLIC_IDLE } from "@/lib/rq/action-state";

export function StartQuoteButton() {
  const [state, formAction, pending] = useActionState(startQuoteAction, PUBLIC_IDLE);

  return (
    <form action={formAction}>
      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-lg bg-slate-900 px-6 py-4 text-base font-semibold text-white transition hover:bg-slate-800 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {pending ? "Starting…" : "Start my roof quote"}
      </button>
      {!state.ok && state.message ? (
        <p className="mt-3 text-sm text-red-600" role="alert">
          {state.message}
        </p>
      ) : null}
    </form>
  );
}