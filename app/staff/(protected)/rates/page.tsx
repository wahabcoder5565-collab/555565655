import type { Metadata } from "next";
import { listRateItems } from "@/lib/rq/staff";
import { RateCardEditor } from "@/components/rate-card-editor";

export const metadata: Metadata = { title: "Rate card" };

export default async function RatesPage() {
  const items = await listRateItems();

  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Rate card</h1>
      <p className="mt-1 text-sm text-slate-600">
        These prices feed the engine directly. Every total a customer sees is
        computed in Postgres from this table, so there is no way to quote around
        it from the browser.
      </p>
      <RateCardEditor items={items} />
    </div>
  );
}
