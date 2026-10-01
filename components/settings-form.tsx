"use client";

import { useActionState } from "react";
import { saveSettingsAction } from "@/app/staff/config-actions";
import { CONFIG_IDLE } from "@/lib/rq/action-state";

const IDLE = CONFIG_IDLE;

type Props = {
  settings: Record<string, unknown>;
};

function str(settings: Props["settings"], key: string, fallback = "") {
  const v = settings[key];
  return v === null || v === undefined ? fallback : String(v);
}

function num(settings: Props["settings"], key: string, fallback = 0) {
  const v = settings[key];
  return v === null || v === undefined ? fallback : Number(v);
}

const TEXT_FIELDS: { name: string; label: string; type?: string; span?: boolean }[] = [
  { name: "company_name", label: "Company name" },
  { name: "contact_email", label: "Contact email", type: "email" },
  { name: "phone", label: "Phone" },
  { name: "license_no", label: "Licence number" },
  { name: "website", label: "Website" },
  { name: "address_line", label: "Address", span: true },
  { name: "city", label: "City" },
  { name: "state", label: "State" },
  { name: "zip_code", label: "Postcode" },
  { name: "currency", label: "Currency" },
  { name: "logo_url", label: "Logo URL", span: true },
];

/** These drive the quote maths, so they are grouped separately from the details. */
const PRICING_FIELDS: { name: string; label: string; hint: string; step: string }[] = [
  { name: "waste_factor_pct", label: "Waste factor %", hint: "Extra material for cuts and offcuts.", step: "0.1" },
  { name: "overhead_pct", label: "Overhead %", hint: "Crew, vehicles, supervision.", step: "0.1" },
  { name: "profit_pct", label: "Profit %", hint: "Your margin.", step: "0.1" },
  { name: "contingency_pct", label: "Contingency %", hint: "Unknowns allowance.", step: "0.1" },
  { name: "tax_pct", label: "Tax %", hint: "Applied to the taxable base.", step: "0.1" },
  { name: "min_charge", label: "Minimum charge", hint: "Floor for very small jobs.", step: "0.01" },
  { name: "deposit_pct", label: "Deposit %", hint: "Shown as the deposit due on acceptance.", step: "0.1" },
  { name: "valid_days", label: "Quote valid for (days)", hint: "Expiry written at issue time.", step: "1" },
  { name: "warranty_years", label: "Warranty (years)", hint: "Printed on the quote.", step: "1" },
];

export function SettingsForm({ settings }: Props) {
  const [state, action, pending] = useActionState(saveSettingsAction, IDLE);

  return (
    <form action={action} className="mt-6 space-y-8">
      <section>
        <h2 className="text-sm font-semibold">Business details</h2>
        <p className="text-xs text-slate-500">
          Printed on every quote the customer sees.
        </p>
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          {TEXT_FIELDS.map((f) => (
            <label
              key={f.name}
              className={`text-xs font-medium text-slate-600 ${f.span ? "sm:col-span-2" : ""}`}
            >
              {f.label}
              <input
                name={f.name}
                type={f.type ?? "text"}
                defaultValue={str(settings, f.name)}
                className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
              />
            </label>
          ))}
          <label className="text-xs font-medium text-slate-600">
            Brand colour
            <span className="mt-1 flex items-center gap-2">
              <input
                type="color"
                name="brand_color"
                defaultValue={str(settings, "brand_color", "#0f172a")}
                className="size-9 cursor-pointer rounded border border-slate-300 bg-white p-0.5"
              />
              <span className="text-xs text-slate-400">Used for headings and the accept button.</span>
            </span>
          </label>
          <label className="text-xs font-medium text-slate-600 sm:col-span-2">
            Terms
            <textarea
              name="terms"
              rows={4}
              defaultValue={str(settings, "terms")}
              className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
            />
          </label>
        </div>
      </section>

      <section>
        <h2 className="text-sm font-semibold">Pricing knobs</h2>
        <p className="text-xs text-slate-500">
          Applied in Postgres at quote time, so these values cannot drift from
          the numbers on an issued quote.
        </p>
        <div className="mt-3 grid gap-3 sm:grid-cols-3">
          {PRICING_FIELDS.map((f) => (
            <label key={f.name} className="text-xs font-medium text-slate-600">
              {f.label}
              <input
                name={f.name}
                type="number"
                step={f.step}
                min="0"
                defaultValue={num(settings, f.name)}
                className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm tabular-nums"
              />
              <span className="mt-1 block text-[11px] font-normal text-slate-400">
                {f.hint}
              </span>
            </label>
          ))}
        </div>
      </section>

      {state.message && (
        <p
          role="status"
          className={`text-sm ${state.ok ? "text-emerald-700" : "text-red-600"}`}
        >
          {state.message}
        </p>
      )}

      <button
        type="submit"
        disabled={pending}
        className="rounded-md bg-slate-900 px-4 py-2 text-sm font-medium text-white disabled:opacity-60"
      >
        {pending ? "Saving…" : "Save settings"}
      </button>
    </form>
  );
}
