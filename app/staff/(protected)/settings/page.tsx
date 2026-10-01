import type { Metadata } from "next";
import { getSettings } from "@/lib/rq/staff";
import { SettingsForm } from "@/components/settings-form";

export const metadata: Metadata = { title: "Settings" };

export default async function SettingsPage() {
  const settings = await getSettings();

  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Settings</h1>
      <p className="mt-1 text-sm text-slate-600">
        Your company profile, terms and the multipliers the engine applies to
        every quote.
      </p>
      <SettingsForm settings={settings} />
    </div>
  );
}
