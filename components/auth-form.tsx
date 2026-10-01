"use client";

import { useActionState, useState } from "react";
import { signInAction, signUpAction } from "@/app/staff/actions";
import { AUTH_IDLE } from "@/lib/rq/action-state";

export function AuthForm() {
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [signInState, signIn, signInPending] = useActionState(signInAction, AUTH_IDLE);
  const [signUpState, signUp, signUpPending] = useActionState(signUpAction, AUTH_IDLE);
  const state = mode === "signin" ? signInState : signUpState;
  const pending = mode === "signin" ? signInPending : signUpPending;
  // The form action must resolve to void, so the state-returning action is wrapped.
  const submit = mode === "signin" ? signIn : signUp;

  return (
    <div className="mx-auto w-full max-w-md px-6 py-16">
      <h1 className="text-3xl font-bold tracking-tight">
        {mode === "signin" ? "Contractor sign in" : "Create your account"}
      </h1>
      <p className="mt-2 text-sm text-slate-600">
        {mode === "signin"
          ? "Manage your rate card, leads and quotes."
          : "Your first account becomes the primary contractor for this deployment."}
      </p>

      <div className="mt-6 grid grid-cols-2 gap-1 rounded-lg bg-slate-200 p-1">
        {(["signin", "signup"] as const).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => setMode(m)}
            className={`rounded-md px-3 py-2 text-sm font-medium transition ${
              mode === m ? "bg-white shadow-sm" : "text-slate-600 hover:text-slate-900"
            }`}
          >
            {m === "signin" ? "Sign in" : "Sign up"}
          </button>
        ))}
      </div>

      <form
        key={mode}
        action={(formData: FormData) => {
          void submit(formData);
        }}
        className="mt-6 space-y-4"
      >
        {mode === "signup" && (
          <>
            <Field label="Company name" name="company_name" autoComplete="organization" />
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="City" name="city" autoComplete="address-level2" />
              <Field label="State" name="state" autoComplete="address-level1" />
            </div>
            <Field label="Phone" name="phone" type="tel" autoComplete="tel" />
          </>
        )}

        <Field label="Email" name="email" type="email" autoComplete="email" required />
        <Field
          label="Password"
          name="password"
          type="password"
          autoComplete={mode === "signin" ? "current-password" : "new-password"}
          required
        />

        <button
          type="submit"
          disabled={pending}
          className="w-full rounded-lg bg-slate-900 px-4 py-3 font-semibold text-white transition hover:bg-slate-800 disabled:opacity-60"
        >
          {pending
            ? "Working…"
            : mode === "signin"
              ? "Sign in"
              : "Create account"}
        </button>

        {state.message ? (
          <p
            role={state.needsConfirmation ? "status" : "alert"}
            className={`rounded-lg px-3 py-2 text-sm ${
              state.needsConfirmation
                ? "bg-sky-50 text-sky-800"
                : "bg-red-50 text-red-700"
            }`}
          >
            {state.message}
          </p>
        ) : null}
      </form>
    </div>
  );
}

function Field({
  label,
  name,
  type = "text",
  autoComplete,
  required,
}: {
  label: string;
  name: string;
  type?: string;
  autoComplete?: string;
  required?: boolean;
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-sm font-medium text-slate-700">{label}</span>
      <input
        name={name}
        type={type}
        autoComplete={autoComplete}
        required={required}
        className="w-full rounded-lg border border-slate-300 px-3 py-2 text-sm outline-none focus:border-slate-900 focus:ring-2 focus:ring-slate-900/10"
      />
    </label>
  );
}