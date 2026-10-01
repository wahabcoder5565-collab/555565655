"use client";

import { useState, useTransition } from "react";
import { saveAnswersAction, submitQuoteAction } from "@/app/actions/public";
import type {
  AnswerValue,
  Answers,
  PublicLead,
  Question,
} from "@/lib/rq/types";

type Step = {
  section: string;
  questions: Question[];
};

const SECTION_TITLES: Record<string, string> = {
  contact: "About you",
  property: "Your property",
  roof: "Your roof",
  scope: "Scope of work",
  access: "Access and safety",
  timeline: "Timing",
  other: "Anything else",
};

function titleFor(section: string) {
  return (
    SECTION_TITLES[section] ??
    section.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase())
  );
}

/**
 * Stored option values are snake_case and machine readable ("3tab",
 * "self_adhered"). Those are submitted to Postgres verbatim, so only the
 * displayed text is prettified here.
 */
function formatOptionLabel(value: string) {
  return value.replace(/_/g, " ").replace(/^./, (c) => c.toUpperCase());
}

/** Preserves the order sections first appear in, so the DB ordering wins. */
function buildSteps(questions: Question[]): Step[] {
  const steps: Step[] = [];
  for (const q of questions) {
    const existing = steps.find((s) => s.section === q.section);
    if (existing) existing.questions.push(q);
    else steps.push({ section: q.section, questions: [q] });
  }
  return steps;
}

export function QuoteWizard({
  token,
  lead,
  questions,
}: {
  token: string;
  lead: PublicLead;
  questions: Question[];
}) {
  const steps = buildSteps(questions);
  // One extra step collects the contact details before submitting.
  const total = steps.length + 1;

  const [index, setIndex] = useState(() =>
    Math.min(Math.max(lead.current_step ?? 0, 0), steps.length),
  );
  const [answers, setAnswers] = useState<Answers>(() => ({ ...lead.answers }));
  const [contact, setContact] = useState({
    name: lead.contact.contact_name ?? "",
    email: lead.contact.contact_email ?? "",
    phone: lead.contact.contact_phone ?? "",
  });
  const [error, setError] = useState<string | null>(null);
  const [missing, setMissing] = useState<string[]>([]);
  const [pending, startTransition] = useTransition();

  const onContactStep = index === steps.length;
  const step = steps[index];
  const progress = Math.round(((index + 1) / total) * 100);

  function setAnswer(key: string, value: AnswerValue) {
    setAnswers((prev) => ({ ...prev, [key]: value }));
    setMissing((prev) => prev.filter((k) => k !== key));
  }

  function goNext() {
    setError(null);
    startTransition(async () => {
      const res = await saveAnswersAction(token, answers, index + 1, contact);
      if (!res.ok) {
        setError(res.message);
        return;
      }
      setIndex((i) => Math.min(i + 1, steps.length));
      window.scrollTo({ top: 0, behavior: "smooth" });
    });
  }

  function goBack() {
    setError(null);
    setIndex((i) => Math.max(i - 1, 0));
  }

  function submit() {
    setError(null);
    startTransition(async () => {
      // Persist the contact fields first; rq_public_submit reads them from the
      // lead row rather than from the request.
      const saved = await saveAnswersAction(token, answers, index, contact);
      if (!saved.ok) {
        setError(saved.message);
        return;
      }
      const res = await submitQuoteAction(token);
      if (!res.ok) {
        setError(res.message);
        setMissing(res.missing ?? []);
        return;
      }
      // On success the action redirects, so reaching here means nothing to do.
    });
  }

  return (
    <div className="mx-auto w-full max-w-2xl px-6 py-10">
      <header>
        <p className="text-xs font-semibold uppercase tracking-wide text-slate-400">
          {lead.contractor.company_name}
        </p>
        <h1 className="mt-1 text-3xl font-bold tracking-tight">
          {onContactStep ? "Where should we send the quote?" : titleFor(step.section)}
        </h1>
        <div className="mt-6 flex items-center gap-3">
          <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-slate-200">
            <div
              className="h-full rounded-full bg-slate-900 transition-all"
              style={{ width: `${progress}%` }}
            />
          </div>
          <span className="shrink-0 text-xs tabular-nums text-slate-500">
            Step {index + 1} of {total}
          </span>
        </div>
      </header>

      <div className="mt-8 space-y-6">
        {onContactStep ? (
          <ContactFields contact={contact} setContact={setContact} />
        ) : (
          step.questions.map((q) => (
            <QuestionField
              key={q.key}
              question={q}
              value={answers[q.key]}
              invalid={missing.includes(q.key)}
              onChange={(v) => setAnswer(q.key, v)}
            />
          ))
        )}
      </div>

      {error && (
        <p
          role="alert"
          className="mt-6 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700"
        >
          {error}
        </p>
      )}

      <div className="mt-8 flex items-center gap-3">
        {index > 0 && (
          <button
            type="button"
            onClick={goBack}
            disabled={pending}
            className="rounded-lg border border-slate-300 px-5 py-3 font-medium text-slate-600 disabled:opacity-60"
          >
            Back
          </button>
        )}
        <button
          type="button"
          onClick={onContactStep ? submit : goNext}
          disabled={pending}
          className="flex-1 rounded-lg bg-slate-900 px-5 py-3 font-semibold text-white transition hover:bg-slate-800 disabled:opacity-60"
        >
          {pending
            ? "Working…"
            : onContactStep
              ? "Get my quote"
              : "Continue"}
        </button>
      </div>

      <p className="mt-6 text-xs text-slate-400">
        Your answers are priced in our database. Nothing you type can change a
        rate directly.
      </p>
    </div>
  );
}

function ContactFields({
  contact,
  setContact,
}: {
  contact: { name: string; email: string; phone: string };
  setContact: (c: { name: string; email: string; phone: string }) => void;
}) {
  return (
    <>
      <Field
        label="Full name"
        required
        value={contact.name}
        onChange={(v) => setContact({ ...contact, name: v })}
        autoComplete="name"
      />
      <Field
        label="Email"
        type="email"
        required
        value={contact.email}
        onChange={(v) => setContact({ ...contact, email: v })}
        help="We will send your quote to this address."
        autoComplete="email"
      />
      <Field
        label="Phone"
        type="tel"
        value={contact.phone}
        onChange={(v) => setContact({ ...contact, phone: v })}
        help="Optional, but it speeds things up."
        autoComplete="tel"
      />
    </>
  );
}

function Field({
  label,
  value,
  onChange,
  type = "text",
  required,
  help,
  autoComplete,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
  required?: boolean;
  help?: string;
  autoComplete?: string;
}) {
  return (
    <label className="block text-sm">
      <span className="font-medium text-slate-700">
        {label}
        {required && <span className="ml-0.5 text-red-500">*</span>}
      </span>
      <input
        type={type}
        value={value}
        required={required}
        autoComplete={autoComplete}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1 w-full rounded-lg border border-slate-300 px-3 py-2.5 outline-none focus:border-slate-900"
      />
      {help && <span className="mt-1 block text-xs text-slate-400">{help}</span>}
    </label>
  );
}

function QuestionField({
  question,
  value,
  onChange,
  invalid,
}: {
  question: Question;
  value: AnswerValue | undefined;
  onChange: (v: AnswerValue) => void;
  invalid: boolean;
}) {
  const [showHelp, setShowHelp] = useState(false);
  const base = invalid ? "border-red-400" : "border-slate-300";

  const control = () => {
    switch (question.input_type) {
      case "number":
        return (
          <div className="flex items-center gap-2">
            <input
              type="number"
              value={value === null || value === undefined ? "" : String(value)}
              min={question.min_value ?? undefined}
              max={question.max_value ?? undefined}
              step={question.step_value ?? "any"}
              onChange={(e) =>
                onChange(e.target.value === "" ? null : Number(e.target.value))
              }
              className={`w-full rounded-lg border px-3 py-2.5 tabular-nums outline-none focus:border-slate-900 ${base}`}
            />
            {question.unit && (
              <span className="shrink-0 text-sm text-slate-500">{question.unit}</span>
            )}
          </div>
        );

      case "select":
      case "radio":
        return (
          <select
            value={typeof value === "string" ? value : ""}
            onChange={(e) => onChange(e.target.value === "" ? null : e.target.value)}
            className={`w-full rounded-lg border bg-white px-3 py-2.5 outline-none focus:border-slate-900 ${base}`}
          >
            <option value="">Choose…</option>
            {question.options.map((o) => (
              <option key={o} value={o}>
                {formatOptionLabel(o)}
              </option>
            ))}
          </select>
        );

      case "multi_select": {
        const chosen = Array.isArray(value) ? (value as string[]) : [];
        return (
          <div className="flex flex-wrap gap-2">
            {question.options.map((o) => {
              const on = chosen.includes(o);
              return (
                <button
                  key={o}
                  type="button"
                  aria-pressed={on}
                  onClick={() =>
                    onChange(
                      on ? chosen.filter((v) => v !== o) : [...chosen, o],
                    )
                  }
                  className={`rounded-full border px-3 py-1.5 text-sm transition ${
                    on
                      ? "border-slate-900 bg-slate-900 text-white"
                      : "border-slate-300 text-slate-600 hover:border-slate-500"
                  }`}
                >
                  {formatOptionLabel(o)}
                </button>
              );
            })}
          </div>
        );
      }

      case "boolean":
        return (
          <div className="flex gap-2">
            {[
              { v: "Yes", b: true },
              { v: "No", b: false },
            ].map((opt) => (
              <button
                key={opt.v}
                type="button"
                aria-pressed={value === opt.b}
                onClick={() => onChange(opt.b)}
                className={`rounded-lg border px-4 py-2 text-sm transition ${
                  value === opt.b
                    ? "border-slate-900 bg-slate-900 text-white"
                    : "border-slate-300 text-slate-600 hover:border-slate-500"
                }`}
              >
                {opt.v}
              </button>
            ))}
          </div>
        );

      default:
        return (
          <textarea
            rows={3}
            value={typeof value === "string" ? value : ""}
            onChange={(e) => onChange(e.target.value === "" ? null : e.target.value)}
            className={`w-full rounded-lg border px-3 py-2.5 outline-none focus:border-slate-900 ${base}`}
          />
        );
    }
  };

  return (
    <div>
      <div className="flex items-baseline justify-between gap-3">
        <label className="block text-sm">
          <span className="font-medium text-slate-700">
            {question.label}
            {question.required && <span className="ml-0.5 text-red-500">*</span>}
          </span>
        </label>
        {question.help_text && (
          <button
            type="button"
            onClick={() => setShowHelp((v) => !v)}
            className="shrink-0 text-xs text-slate-400 underline"
            aria-expanded={showHelp}
          >
            {showHelp ? "hide" : "why we ask"}
          </button>
        )}
      </div>

      {showHelp && question.help_text && (
        <p className="mt-1 text-xs text-slate-500">{question.help_text}</p>
      )}

      <div className="mt-1.5">{control()}</div>

      {invalid && (
        <p className="mt-1 text-xs text-red-600">This one is required.</p>
      )}
    </div>
  );
}
