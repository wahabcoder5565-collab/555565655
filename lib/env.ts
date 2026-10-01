/**
 * Supabase connection settings.
 *
 * Both values are safe to ship to the browser: the publishable key is the
 * replacement for the legacy anon key and is only meaningful in combination
 * with RLS. Everything that matters commercially lives behind RLS plus the
 * grant allow-list in migration 0015, so the browser can hold this key without
 * it being a credential.
 */

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const key =
  process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

export type SupabaseEnv = {
  url: string;
  key: string;
};

export function requireSupabaseEnv(): SupabaseEnv {
  const missing: string[] = [];
  if (!url) missing.push("NEXT_PUBLIC_SUPABASE_URL");
  if (!key)
    missing.push("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY (or NEXT_PUBLIC_SUPABASE_ANON_KEY)");

  if (missing.length > 0) {
    throw new Error(
      `Missing Supabase environment variable(s): ${missing.join(", ")}. ` +
        `Add them to .env.local and restart the dev server.`,
    );
  }

  return { url: url as string, key: key as string };
}