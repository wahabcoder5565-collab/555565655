/**
 * Initial state for the useActionState hooks that drive the forms.
 *
 * These live here rather than alongside the actions because a "use server"
 * module may only export async functions, so a plain object cannot be exported
 * from one. The result types stay with the actions themselves, where they are
 * type-only exports and therefore erased at build time.
 */

export type ActionState = {
  ok: boolean;
  message: string;
  /** Keys rq_public_submit reported as required but unanswered. */
  missing?: string[];
};

export type AuthState = {
  ok: boolean;
  message: string;
  needsConfirmation: boolean;
};

export const PUBLIC_IDLE: ActionState = { ok: false, message: "" };

export const CONFIG_IDLE: ActionState = { ok: false, message: "" };

export const AUTH_IDLE: AuthState = { ok: false, message: "", needsConfirmation: false };
