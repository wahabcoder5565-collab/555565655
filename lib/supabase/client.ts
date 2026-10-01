import { createBrowserClient } from "@supabase/ssr";
import { requireSupabaseEnv } from "@/lib/env";

/**
 * Browser Supabase client. Call inside a Client Component.
 *
 * createBrowserClient caches its own instance per browser context, so it is
 * safe to construct at module scope inside 'use client' modules, but this
 * helper reads env lazily so an import in a module that renders on the server
 * first does not explode during SSR.
 */
export function createClient() {
  const { url, key } = requireSupabaseEnv();
  return createBrowserClient(url, key);
}