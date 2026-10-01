"use client";

import { useActionState, useState } from "react";
import type { StaffRateItem } from "@/lib/rq/types";
import { resetRateItemsAction, saveRateItemAction } from "@/app/staff/config-actions";
import { CONFIG_IDLE } from "@/lib/rq/action-state";

const IDLE = CONFIG_IDLE;

const UNITS = ["sqft", "square", "linear_ft", "each", "sheet", "hour"];
const CATEGORIES = [
  "material",
  "underlayment",
  "accessory",
  "teardown",
  "disposal",
  "labor",
  "permit",
  "protection",
];

/**
 * Editing a row the contractor has not overridden writes an override copy, so
 * the inherited system price is never mutated. Inherited rows are marked and
 * can be restored with the reset action.
 */
export function RateCardEditor({ items }: { items: StaffRateItem[] }) {
  const [filter, setFilter] = useState("");

  // The list is rendered straight from the server props. Mutations revalidate
  // the page, so no mirrored copy is kept here that could drift out of date.

  const visible = filter
    ? items.filter((r) =>
        `${r.code} ${r.label} ${r.category}`.toLowerCase().includes(filter.toLowerCase()),
      )
    : items;

  const grouped = visible.reduce<Record<string, StaffRateItem[]>>((acc, r) => {
    (acc[r.category] ??= []).push(r);
    return acc;
  }, {});

  return (
    <div>
      <div className="mt-6 flex flex-wrap items-center gap-3">
        <input
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
          placeholder="Filter rate card…"
          className="flex-1 rounded-md border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-900"
        />
        <ResetButton />
      </div>

      <p className="mt-2 text-xs text-slate-500">
        {items.filter((r) => r.is_override).length} of {items.length} rows overridden.
        Saving an inherited row creates your own copy and leaves the shared
        template untouched.
      </p>

      <div className="mt-4 space-y-6">
        {Object.entries(grouped).map(([category, list]) => (
          <section key={category}>
            <h2 className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              {category}
            </h2>
            <div className="mt-2 space-y-2">
              {list.map((item) => (
                <RateRow key={item.id} item={item} />
              ))}
            </div>
          </section>
        ))}
      </div>
    </div>
  );
}

function ResetButton() {
  const [confirming, setConfirming] = useState(false);
  return (
    <button
      type="button"
      onClick={async () => {
        if (!confirming) {
          setConfirming(true);
          return;
        }
        await resetRateItemsAction();
      }}
      onBlur={() => setConfirming(false)}
      className="rounded-md border border-slate-300 px-3 py-2 text-sm text-slate-600 hover:bg-slate-50"
    >
      {confirming ? "Confirm: drop overrides" : "Reset to system rates"}
    </button>
  );
}

function RateRow({ item }: { item: StaffRateItem }) {
  const [open, setOpen] = useState(false);
  const [state, action, pending] = useActionState(saveRateItemAction, IDLE);

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex w-full items-center gap-3 rounded-lg border border-slate-200 bg-white px-4 py-2.5 text-left text-sm hover:border-slate-400"
      >
        <span className="flex-1">
          <span className="font-medium">{item.label}</span>
          <span className="ml-2 text-xs text-slate-400">{item.code}</span>
        </span>
        {item.is_override && (
          <span className="rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-800">
            overridden
          </span>
        )}
        {!item.is_active && (
          <span className="rounded-full bg-slate-200 px-2 py-0.5 text-[11px] text-slate-600">
            inactive
          </span>
        )}
        <span className="tabular-nums text-slate-600">
          ${Number(item.unit_price).toFixed(2)}
          <span className="ml-1 text-xs text-slate-400">/{item.unit}</span>
        </span>
      </button>
    );
  }

  return (
    <form action={action} className="rounded-lg border border-slate-300 bg-slate-50 p-4">
      <input type="hidden" name="id" value={item.id} />
      <input type="hidden" name="code" value={item.code} />
      <input type="hidden" name="sort_order" value={item.sort_order} />

      <div className="grid gap-3 sm:grid-cols-4">
        <label className="text-xs font-medium text-slate-600 sm:col-span-2">
          Label
          <input
            name="label"
            defaultValue={item.label}
            required
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Price
          <input
            name="unit_price"
            type="number"
            step="0.01"
            min="0"
            defaultValue={item.unit_price}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm tabular-nums"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Unit
          <select
            name="unit"
            defaultValue={item.unit}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          >
            {UNITS.map((u) => (
              <option key={u} value={u}>
                {u}
              </option>
            ))}
          </select>
        </label>
        <label className="text-xs font-medium text-slate-600 sm:col-span-2">
          Description
          <input
            name="description"
            defaultValue={item.description}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Category
          <select
            name="category"
            defaultValue={item.category}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          >
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
        <label className="flex items-end gap-2 pb-1.5 text-xs font-medium text-slate-600">
          <input
            type="checkbox"
            name="is_active"
            defaultChecked={item.is_active}
            className="size-4 rounded border-slate-300"
          />
          Active
        </label>
      </div>

      {state.message && (
        <p
          className={`mt-3 text-xs ${state.ok ? "text-emerald-700" : "text-red-600"}`}
          role="status"
        >
          {state.message}
        </p>
      )}

      <div className="mt-3 flex gap-2">
        <button
          type="submit"
          disabled={pending}
          className="rounded-md bg-slate-900 px-3 py-1.5 text-sm font-medium text-white disabled:opacity-60"
        >
          {pending ? "Saving…" : "Save"}
        </button>
        <button
          type="button"
          onClick={() => setOpen(false)}
          className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600"
        >
          Cancel
        </button>
      </div>
    </form>
  );
}
