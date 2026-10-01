"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { AuthState } from "@/lib/rq/action-state";

export type { AuthState };

function describe(error: { message: string } | null): string {
  if (!error) return "Unknown error.";
  // Supabase prefixes some messages with "AuthApiError:".
  return error.message.replace(/^AuthApiError:\s*/, "");
}

export async function signInAction(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  if (!email || !password) {
    return { ok: false, message: "Email and password are required.", needsConfirmation: false };
  }

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return { ok: false, message: describe(error), needsConfirmation: false };

  redirect("/staff");
}

export async function signUpAction(
  _prev: AuthState,
  formData: FormData,
): Promise<AuthState> {
  const companyName = String(formData.get("company_name") ?? "").trim();
  const email = String(formData.get("email") ?? "").trim();
  const password = String(formData.get("password") ?? "");
  const phone = String(formData.get("phone") ?? "").trim();
  const city = String(formData.get("city") ?? "").trim();
  const state = String(formData.get("state") ?? "").trim();

  if (!email || !password) {
    return { ok: false, message: "Email and password are required.", needsConfirmation: false };
  }
  if (password.length < 8) {
    return { ok: false, message: "Use a password of at least 8 characters.", needsConfirmation: false };
  }

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      // rq_on_auth_user_created reads these to seed the contractor row, so the
      // first genuine signup becomes the primary contractor.
      // rq_app is required: this Supabase project is shared with other apps and
      // the trigger fires on every auth.users insert, so the marker is what
      // distinguishes a roofer from an unrelated signup.
      data: {
        rq_app: "roofing",
        company_name: companyName,
        phone,
        city,
        state,
      },
    },
  });

  if (error) return { ok: false, message: describe(error), needsConfirmation: false };

  // When email confirmation is enabled there is no session yet and the user has
  // to confirm before they can sign in.
  if (!data.session) {
    return {
      ok: false,
      message: "Account created. Check your email to confirm the address, then sign in.",
      needsConfirmation: true,
    };
  }

  redirect("/staff");
}

export async function signOutAction(): Promise<void> {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/staff/login");
}