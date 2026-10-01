import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getQuote } from "@/lib/rq/staff";
import { StatusSelect } from "@/components/status-select";
import { GenerateScopeButton } from "@/components/generate-scope-button";

export const metadata: Metadata = { title: "Quote" };

const MONEY = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

export default async function QuoteDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  // The RPC raises no_data_found for an unknown or other-tenant quote, so a
  // missing id and a forbidden id are indistinguishable on purpose.
  let detail: Awaited<ReturnType<typeof getQuote>>;
  try {
    detail = await getQuote(id);
  } catch {
    notFound();
  }

  const { quote, lead, items, events, public_url_token } = detail;

  return (
    <div>
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{quote.quote_number}</h1>
          <p className="mt-1 text-sm text-slate-600">
            {lead ? (
              <>
                {lead.contact_name} &middot; {lead.property_address}
              </>
            ) : (
              "Lead unavailable"
            )}
          </p>
          <p className="mt-1 text-xs text-slate-400">
            Issued {new Date(quote.created_at).toLocaleDateString()} &middot; valid until{" "}
            {new Date(quote.valid_until).toLocaleDateString()}
          </p>
        </div>
        <div className="flex items-center gap-3">
          <StatusSelect id={quote.id} kind="quote" value={quote.status} />
          <a
            href={`/quote/${public_url_token}`}
            target="_blank"
            rel="noreferrer"
            className="rounded-lg border border-slate-300 px-3 py-2 text-sm font-medium hover:bg-slate-50"
          >
            Customer view
          </a>
        </div>
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-[2fr_1fr]">
        <div className="space-y-6">
          <section className="overflow-hidden rounded-xl border border-slate-200 bg-white">
            <h2 className="border-b border-slate-200 px-4 py-3 text-sm font-semibold">
              Priced from the database
            </h2>
            <table className="w-full text-sm">
              <tbody className="divide-y divide-slate-100">
                {items.map((item, i) => (
                  <tr key={`${item.code}-${i}`}>
                    <td className="px-4 py-2">
                      {item.label}
                      {item.quantity !== 1 && (
                        <span className="text-slate-400">
                          {" "}
                          &times; {item.quantity} {item.unit}
                        </span>
                      )}
                    </td>
                    <td className="px-4 py-2 text-right tabular-nums text-slate-600">
                      {MONEY.format(item.line_total)}
                    </td>
                  </tr>
                ))}
                <tr className="bg-slate-50 font-semibold">
                  <td className="px-4 py-2">Total</td>
                  <td className="px-4 py-2 text-right tabular-nums">
                    {MONEY.format(quote.total)}
                  </td>
                </tr>
                <tr className="text-slate-600">
                  <td className="px-4 py-2">Deposit due</td>
                  <td className="px-4 py-2 text-right tabular-nums">
                    {MONEY.format(quote.deposit_amount)}
                  </td>
                </tr>
              </tbody>
            </table>
          </section>

          <section className="rounded-xl border border-slate-200 bg-white p-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <h2 className="text-sm font-semibold">Written scope of work</h2>
              <GenerateScopeButton quoteId={quote.id} status={quote.ai_status ?? null} />
            </div>

            {quote.ai_error && (
              <p className="mt-3 rounded-lg bg-amber-50 p-3 text-xs text-amber-800">
                Last generation failed: {quote.ai_error}
              </p>
            )}

            {quote.ai_scope_of_work ? (
              <div className="mt-3 space-y-4 text-sm leading-relaxed text-slate-700">
                {quote.ai_summary && (
                  <div>
                    <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                      Summary
                    </h3>
                    <p className="mt-1">{quote.ai_summary}</p>
                  </div>
                )}
                <div>
                  <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    Scope
                  </h3>
                  <p className="mt-1 whitespace-pre-line">{quote.ai_scope_of_work}</p>
                </div>
                <AiList
                  title="Recommendations"
                  value={quote.ai_recommendations}
                />
                <AiList title="Risk notes" value={quote.ai_risk_notes} />
                {(quote.ai_engine || quote.ai_model) && (
                  <p className="text-xs text-slate-400">
                    Generated by {quote.ai_engine ?? "deterministic engine"}
                    {quote.ai_model ? ` / ${quote.ai_model}` : ""}
                  </p>
                )}
              </div>
            ) : (
              <p className="mt-3 text-sm text-slate-500">
                No written scope yet. Generate one to draft the narrative for this
                quote. Totals always come from the database and are never changed
                by this.
              </p>
            )}
          </section>
        </div>

        <aside className="space-y-6">
          <section className="rounded-xl border border-slate-200 bg-white p-4">
            <h2 className="text-sm font-semibold">Activity</h2>
            {events.length === 0 ? (
              <p className="mt-2 text-sm text-slate-500">Nothing recorded yet.</p>
            ) : (
              <ol className="mt-2 space-y-2 text-xs text-slate-600">
                {events.map((event) => (
                  <li key={event.id}>
                    <span className="font-medium">{event.action}</span>
                    {event.detail && <span className="text-slate-500"> — {event.detail}</span>}
                    <span className="block text-slate-400">
                      {new Date(event.created_at).toLocaleString()}
                    </span>
                  </li>
                ))}
              </ol>
            )}
          </section>

          <p className="text-xs text-slate-400">
            <Link href="/staff/quotes" className="underline">
              Back to quotes
            </Link>
          </p>
        </aside>
      </div>
    </div>
  );
}

function AiList({ title, value }: { title: string; value: unknown }) {
  const items = Array.isArray(value)
    ? value.filter((v): v is string => typeof v === "string")
    : typeof value === "string" && value.trim()
      ? [value]
      : [];

  if (items.length === 0) return null;

  return (
    <div>
      <h3 className="text-xs font-semibold uppercase tracking-wide text-slate-500">
        {title}
      </h3>
      <ul className="mt-1 list-disc space-y-1 pl-5">
        {items.map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </div>
  );
}