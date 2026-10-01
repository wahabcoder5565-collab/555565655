import type { Metadata } from "next";
import Link from "next/link";
import { listQuotes } from "@/lib/rq/staff";
import { StatusSelect } from "@/components/status-select";

export const metadata: Metadata = { title: "Quotes" };

const MONEY = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

export default async function QuotesPage() {
  const { rows: quotes, total } = await listQuotes({ limit: 100 });

  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Quotes</h1>
      <p className="mt-1 text-sm text-slate-600">
        Every issued quote. Totals are snapshotted at issue, so later rate card
        edits do not rewrite history.
      </p>

      {quotes.length === 0 ? (
        <p className="mt-8 rounded-xl border border-dashed border-slate-300 p-8 text-center text-sm text-slate-500">
          No quotes yet.
        </p>
      ) : (
        <>
          <p className="mt-4 text-xs text-slate-500">
            Showing {quotes.length} of {total}
            {total > quotes.length ? " — narrow the list to see older ones." : ""}
          </p>
          <div className="mt-2 overflow-x-auto rounded-xl border border-slate-200 bg-white">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-200 bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-3 font-medium">Number</th>
                  <th className="px-4 py-3 font-medium">Customer</th>
                  <th className="px-4 py-3 font-medium">Project</th>
                  <th className="px-4 py-3 text-right font-medium">Total</th>
                  <th className="px-4 py-3 text-right font-medium">Deposit</th>
                  <th className="px-4 py-3 font-medium">AI</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 font-medium">Valid until</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {quotes.map((quote) => (
                  <tr key={quote.id}>
                    <td className="px-4 py-3">
                      <Link
                        href={`/staff/quotes/${quote.id}`}
                        className="font-medium underline"
                      >
                        {quote.quote_number}
                      </Link>
                    </td>
                    <td className="px-4 py-3 text-slate-600">
                      {quote.contact_name || "—"}
                    </td>
                    <td className="px-4 py-3 text-xs text-slate-500">
                      {quote.property_address || "—"}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      {MONEY.format(quote.total)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums text-slate-600">
                      {MONEY.format(quote.deposit_amount)}
                    </td>
                    <td className="px-4 py-3 text-xs text-slate-500">
                      {quote.ai_status || "—"}
                    </td>
                    <td className="px-4 py-3">
                      <StatusSelect id={quote.id} kind="quote" value={quote.status} />
                    </td>
                    <td className="px-4 py-3 text-xs text-slate-500">
                      {quote.valid_until
                        ? new Date(quote.valid_until).toLocaleDateString()
                        : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}