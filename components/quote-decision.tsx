"use client";

import { useState, useTransition } from "react";
import { respondAction } from "@/app/actions/public";

export function QuoteDecision({
  quoteToken,
  status,
  total,
}: {
  quoteToken: string;
  status: string;
  total: string;
}) {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const decided = status === "accepted" || status === "declined";

  function decide(decision: "accepted" | "declined") {
    setError(null);
    startTransition(async () => {
      const res = await respondAction(quoteToken, decision);
      if (!res.ok) setError(res.message);
    });
  }

  if (decided) {
    return (
      <div
        className={`mt-8 rounded-xl border p-6 text-center ${
          status === "accepted"
            ? "border-emerald-300 bg-emerald-50"
            : "border-slate-300 bg-slate-50"
        }`}
      >
        <p className="text-lg font-semibold">
          {status === "accepted" ? "Quote accepted" : "Quote declined"}
        </p>
        <p className="mt-1 text-sm text-slate-600">
          {status === "accepted"
            ? "Thank you. We will be in touch to schedule the work."
            : "No problem. You can reopen this link any time before it expires."}
        </p>
      </div>
    );
  }

  return (
    <div className="mt-8">
      <div className="flex flex-col gap-3 sm:flex-row">
        <button
          type="button"
          onClick={() => decide("accepted")}
          disabled={pending}
          className="flex-1 rounded-lg bg-emerald-700 px-5 py-3.5 font-semibold text-white transition hover:bg-emerald-800 disabled:opacity-60"
        >
          {pending ? "Working…" : `Accept ${total}`}
        </button>
        <button
          type="button"
          onClick={() => decide("declined")}
          disabled={pending}
          className="rounded-lg border border-slate-300 px-5 py-3.5 font-medium text-slate-600 transition hover:bg-slate-50 disabled:opacity-60"
        >
          Decline
        </button>
      </div>
      {error && (
        <p role="alert" className="mt-3 text-sm text-red-600">
          {error}
        </p>
      )}
      <p className="mt-3 text-xs text-slate-400">
        Accepting records your decision against this quote. No payment is taken
        here.
      </p>
    </div>
  );
}
