import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AuthForm } from "@/components/auth-form";

export const metadata: Metadata = { title: "Staff sign in" };

export default async function StaffLoginPage() {
  const supabase = await createClient();
  const { data } = await supabase.auth.getClaims();
  if (data?.claims.sub) redirect("/staff");

  return (
    <main className="flex-1">
      <AuthForm />
    </main>
  );
}