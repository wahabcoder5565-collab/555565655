import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { signOutAction } from "@/app/staff/actions";

/**
 * Auth guard for the staff area.
 *
 * The login page deliberately lives outside this group (app/staff/login) so the
 * guard cannot redirect an unauthenticated visitor into a loop.
 */
const NAV = [
  { href: "/staff", label: "Dashboard" },
  { href: "/staff/leads", label: "Leads" },
  { href: "/staff/quotes", label: "Quotes" },
  { href: "/staff/rates", label: "Rate card" },
  { href: "/staff/questions", label: "Questions" },
  { href: "/staff/settings", label: "Settings" },
];

export default async function ProtectedStaffLayout({
  children,
}: LayoutProps<"/staff">) {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (!data?.claims.sub) redirect("/staff/login");

  return (
    <div className="flex min-h-screen flex-col">
      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex w-full max-w-6xl flex-wrap items-center gap-4 px-6 py-3">
          <Link href="/staff" className="font-semibold tracking-tight">
            Roof Quote
          </Link>
          <nav className="flex flex-1 flex-wrap gap-1">
            {NAV.map((item) => (
              <Link
                key={item.href}
                href={item.href}
                className="rounded-md px-3 py-1.5 text-sm text-slate-600 transition hover:bg-slate-100 hover:text-slate-900"
              >
                {item.label}
              </Link>
            ))}
          </nav>
          <form action={signOutAction}>
            <button
              type="submit"
              className="rounded-md px-3 py-1.5 text-sm text-slate-500 hover:bg-slate-100 hover:text-slate-900"
            >
              Sign out
            </button>
          </form>
        </div>
      </header>
      <main className="mx-auto w-full max-w-6xl flex-1 px-6 py-8">{children}</main>
    </div>
  );
}
