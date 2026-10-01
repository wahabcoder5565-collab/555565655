import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { requireSupabaseEnv } from "@/lib/env";

/**
 * Request-scoped Supabase client for Server Components, Server Actions and
 * Route Handlers.
 *
 * Next 16 makes cookies() async, so this is an async function. A fresh client
 * is built per call because cookie-backed clients are per-request by nature.
 *
 * setAll is wired up but guarded: Server Components cannot mutate cookies, so
 * writing there is a no-op and only Route Handlers, Server Actions and proxy.ts
 * actually persist a refreshed token.
 */
export async function createClient() {
  const { url, key } = requireSupabaseEnv();
  const cookieStore = await cookies();

  return createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Called from a Server Component: cookies are read-only here.
          // proxy.ts refreshes the session for these routes, so this is safe.
        }
      },
    },
  });
}