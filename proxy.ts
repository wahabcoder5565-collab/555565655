import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { requireSupabaseEnv } from "@/lib/env";

/**
 * Session refresh for the staff area.
 *
 * Server Components cannot write cookies, so if an access token expires while a
 * staff page is being rendered the refreshed token is dropped and the user is
 * signed out at the next navigation. This runs before rendering, validates the
 * JWT locally with getClaims(), and writes any rotated cookies back onto the
 * response.
 *
 * Next 16 requires the nodejs runtime here (edge is unsupported) and exports the
 * function under the name `proxy`. matcher values must be static.
 */
export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request });
  const { url, key } = requireSupabaseEnv();

  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });

  // getClaims() verifies the JWT signature locally and only hits the auth
  // server to refresh the token when it is actually stale.
  await supabase.auth.getClaims();

  return response;
}

export const config = {
  matcher: ["/staff/:path*"],
};