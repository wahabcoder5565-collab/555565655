"use client";

import { useTransition } from "react";
import {
  setLeadStatusAction,
  setQuoteStatusAction,
} from "@/app/staff/config-actions";

const LEAD_STATUSES = ["draft", "submitted", "quoted", "contacted", "won", "lost"];
const QUOTE_STATUSES = ["draft", "sent", "viewed", "accepted", "declined", "expired"];

/**
 * Inline status control. revalidatePath inside the action refreshes the server
 * component list, so no client cache juggling is needed here.
 */
export function StatusSelect({
  id,
  kind,
  value,
}: {
  id: string;
  kind: "lead" | "quote";
  value: string;
}) {
  const [pending, start] = useTransition();
  const options = kind === "lead" ? LEAD_STATUSES : QUOTE_STATUSES;

  return (
    <select
      value={value}
      disabled={pending}
      onChange={(e) => {
        const next = e.target.value;
        start(async () => {
          if (kind === "lead") await setLeadStatusAction(id, next);
          else await setQuoteStatusAction(id, next);
        });
      }}
      className="rounded-md border border-slate-300 bg-white px-2 py-1 text-sm capitalize outline-none focus:border-slate-900 disabled:opacity-60"
    >
      {options.map((s) => (
        <option key={s} value={s} className="capitalize">
          {s}
        </option>
      ))}
    </select>
  );
}
