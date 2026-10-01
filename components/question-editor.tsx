"use client";

import { useActionState, useState } from "react";
import type { StaffQuestion } from "@/lib/rq/types";
import { saveQuestionAction } from "@/app/staff/config-actions";
import { CONFIG_IDLE } from "@/lib/rq/action-state";

const INPUT_TYPES = ["number", "select", "multi_select", "boolean", "text"];
const IDLE = CONFIG_IDLE;

/**
 * The engine only prices answers that carry a key it already knows about, so
 * adding a question here cannot invent a line item. Marking one
 * affects_price is a deliberate flag that ties it into the calculation set.
 */
export function QuestionEditor({ questions }: { questions: StaffQuestion[] }) {
  const [adding, setAdding] = useState(false);

  // Rendered straight from the server props; mutations revalidate the page.

  const sections = questions.reduce<Record<string, StaffQuestion[]>>((acc, q) => {
    (acc[q.section] ??= []).push(q);
    return acc;
  }, {});

  return (
    <div className="mt-6 space-y-8">
      <div className="flex items-center justify-between">
        <p className="text-sm text-slate-600">
          {questions.filter((q) => q.is_override).length} of {questions.length}{" "}
          questions overridden.
        </p>
        <button
          type="button"
          onClick={() => setAdding((v) => !v)}
          className="rounded-md bg-slate-900 px-3 py-2 text-sm font-medium text-white"
        >
          {adding ? "Cancel" : "Add question"}
        </button>
      </div>

      {adding && (
        <QuestionForm
          blank
          onSaved={() => setAdding(false)}
        />
      )}

      {Object.entries(sections).map(([section, list]) => (
        <section key={section}>
          <h2 className="text-xs font-semibold uppercase tracking-wide text-slate-500">
            {section}
          </h2>
          <div className="mt-2 overflow-hidden rounded-xl border border-slate-200 bg-white">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-200 bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-2.5 font-medium">Label</th>
                  <th className="px-4 py-2.5 font-medium">Key</th>
                  <th className="px-4 py-2.5 font-medium">Type</th>
                  <th className="px-4 py-2.5 font-medium">Flags</th>
                  <th className="px-4 py-2.5" />
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {list.map((q) => (
                  <QuestionRow key={q.key} question={q} />
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ))}
    </div>
  );
}

function QuestionRow({ question }: { question: StaffQuestion }) {
  const [open, setOpen] = useState(false);

  if (!open) {
    return (
      <tr>
        <td className="px-4 py-2.5">
          <span className="font-medium">{question.label}</span>
          {question.unit && (
            <span className="ml-1 text-xs text-slate-400">({question.unit})</span>
          )}
        </td>
        <td className="px-4 py-2.5 font-mono text-xs text-slate-500">{question.key}</td>
        <td className="px-4 py-2.5 text-xs text-slate-600">{question.input_type}</td>
        <td className="px-4 py-2.5">
          <span className="flex flex-wrap gap-1">
            {question.is_override && <Flag tone="amber">override</Flag>}
            {!question.is_active && <Flag>inactive</Flag>}
            {question.required && <Flag tone="blue">required</Flag>}
            {question.affects_price && <Flag tone="emerald">prices</Flag>}
          </span>
        </td>
        <td className="px-4 py-2.5 text-right">
          <button
            type="button"
            onClick={() => setOpen(true)}
            className="text-sm text-slate-600 underline"
          >
            Edit
          </button>
        </td>
      </tr>
    );
  }

  return (
    <tr>
      <td colSpan={5} className="bg-slate-50 p-4">
        <QuestionForm question={question} onDone={() => setOpen(false)} />
      </td>
    </tr>
  );
}

function QuestionForm({
  question,
  blank = false,
  onSaved,
  onDone,
}: {
  question?: StaffQuestion;
  blank?: boolean;
  onSaved?: () => void;
  onDone?: () => void;
}) {
  const [state, action, pending] = useActionState(
    async (prev: typeof IDLE, form: FormData) => {
      const next = await saveQuestionAction(prev, form);
      if (next.ok) onSaved?.();
      return next;
    },
    IDLE,
  );

  const q = question;
  // A form action must resolve to void, so the state-returning action is wrapped.
  const formAction = (formData: FormData) => {
    void action(formData);
  };

  return (
    <form action={formAction} className="space-y-3">
      {q && <input type="hidden" name="id" value={q.id} />}
      <div className="grid gap-3 sm:grid-cols-3">
        <label className="text-xs font-medium text-slate-600">
          Label
          <input
            name="label"
            required
            defaultValue={q?.label ?? ""}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Key
          <input
            name="key"
            required
            disabled={!blank}
            defaultValue={q?.key ?? ""}
            placeholder="roof_age"
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 font-mono text-sm disabled:bg-slate-100 disabled:text-slate-500"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Type
          <select
            name="input_type"
            defaultValue={q?.input_type ?? "text"}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          >
            {INPUT_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </label>
        <label className="text-xs font-medium text-slate-600">
          Section
          <input
            name="section"
            defaultValue={q?.section ?? "roof"}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Unit
          <input
            name="unit"
            defaultValue={q?.unit ?? ""}
            placeholder="sqft"
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Help text
          <input
            name="help_text"
            defaultValue={q?.help_text ?? ""}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Options
          <input
            name="options_json"
            defaultValue={JSON.stringify(q?.options ?? [])}
            placeholder='["asphalt_shingle","metal"]'
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 font-mono text-xs"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Min
          <input
            name="min_value"
            type="number"
            step="any"
            defaultValue={q?.min_value ?? ""}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm tabular-nums"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Max
          <input
            name="max_value"
            type="number"
            step="any"
            defaultValue={q?.max_value ?? ""}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm tabular-nums"
          />
        </label>
        <label className="text-xs font-medium text-slate-600">
          Step
          <input
            name="step_value"
            type="number"
            step="any"
            defaultValue={q?.step_value ?? ""}
            className="mt-1 w-full rounded-md border border-slate-300 bg-white px-2 py-1.5 text-sm tabular-nums"
          />
        </label>
      </div>

      <div className="flex flex-wrap gap-4 text-xs font-medium text-slate-600">
        <label className="flex items-center gap-1.5">
          <input
            type="checkbox"
            name="required"
            defaultChecked={q?.required ?? false}
            className="size-3.5 rounded border-slate-300"
          />
          Required
        </label>
        <label className="flex items-center gap-1.5">
          <input
            type="checkbox"
            name="affects_price"
            defaultChecked={q?.affects_price ?? false}
            className="size-3.5 rounded border-slate-300"
          />
          Affects price
        </label>
        <label className="flex items-center gap-1.5">
          <input
            type="checkbox"
            name="is_active"
            defaultChecked={q?.is_active ?? true}
            className="size-3.5 rounded border-slate-300"
          />
          Active
        </label>
      </div>

      {state.message && (
        <p
          className={`text-xs ${state.ok ? "text-emerald-700" : "text-red-600"}`}
          role="status"
        >
          {state.message}
        </p>
      )}

      <div className="flex gap-2">
        <button
          type="submit"
          disabled={pending}
          className="rounded-md bg-slate-900 px-3 py-1.5 text-sm font-medium text-white disabled:opacity-60"
        >
          {pending ? "Saving…" : "Save"}
        </button>
        {onDone && (
          <button
            type="button"
            onClick={onDone}
            className="rounded-md border border-slate-300 px-3 py-1.5 text-sm text-slate-600"
          >
            Close
          </button>
        )}
      </div>
    </form>
  );
}

function Flag({
  children,
  tone = "slate",
}: {
  children: React.ReactNode;
  tone?: "slate" | "amber" | "blue" | "emerald";
}) {
  const tones = {
    slate: "bg-slate-200 text-slate-600",
    amber: "bg-amber-100 text-amber-800",
    blue: "bg-blue-100 text-blue-800",
    emerald: "bg-emerald-100 text-emerald-800",
  };
  return (
    <span className={`rounded-full px-2 py-0.5 text-[11px] font-medium ${tones[tone]}`}>
      {children}
    </span>
  );
}
