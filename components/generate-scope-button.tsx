"use client";

import { useActionState } from "react";
import { useFormStatus } from "react-dom";
import {
  generateScopeAction,
  type GenerateScopeState,
} from "@/app/staff/generate-scope-action";

const INITIAL: GenerateScopeState = { error: null };

function Submit() {
  const { pending } = useFormStatus();
  return (
    <button
      type="submit"
      disabled={pending}
      className="rounded-lg bg-slate-900 px-3 py-2 text-sm font-medium text-white hover:bg-slate-700 disabled:opacity-60"
    >
      {pending ? "Generating…" : "Generate scope"}
    </button>
  );
}

export function GenerateScopeButton({
  quoteId,
  status,
}: {
  quoteId: string;
  status: string | null;
}) {
  const [state, formAction] = useActionState(generateScopeAction, INITIAL);

  return (
    <div className="flex flex-col items-end gap-1">
      <form action={formAction}>
        <input type="hidden" name="quoteId" value={quoteId} />
        <Submit />
      </form>
      {state.error && <p className="text-xs text-red-600">{state.error}</p>}
      {!state.error && status && (
        <p className="text-xs text-slate-400">Last run: {status}</p>
      )}
    </div>
  );
}