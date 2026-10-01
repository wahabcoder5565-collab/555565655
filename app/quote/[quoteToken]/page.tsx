import type { Metadata } from "next";
import { getPublicQuote } from "@/lib/rq/public";
import { QuoteDecision } from "@/components/quote-decision";
import type { QuoteItem } from "@/lib/rq/types";

export const metadata: Metadata = { title: "Your quote" };

type Props = {
  params: Promise<{ quoteToken: string }>;
};

const CATEGORY_LABELS: Record<string, string> = {
  material: "Materials",
  underlayment: "Underlayment & protection",
  accessory: "Accessories",
  teardown: "Teardown",
  disposal: "Disposal",
  labor: "Labour",
  permit: "Permits",
};

const money = (v: number, currency: string) =>
  new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: currency || "USD",
    maximumFractionDigits: 2,
  }).format(Number(v));

export default async function QuotePage({ params }: Props) {
  const { quoteToken } = await params;

  const data = await getPublicQuote(quoteToken).catch(() => null);

  if (!data) {
    return (
      <main className="mx-auto max-w-lg px-6 py-24 text-center">
        <h1 className="text-2xl font-bold tracking-tight">Quote not found</h1>
        <p className="mt-3 text-sm text-slate-600">
          This link is not valid. If you expected a quote here, ask your
          contractor to resend it.
        </p>
      </main>
    );
  }

  const { quote, items, customer, contractor } = data;
  const currency = "USD";
  const address = [
    customer.property_address,
    [customer.property_city, customer.property_state, customer.property_zip]
      .filter(Boolean)
      .join(" "),
  ]
    .filter(Boolean)
    .join(", ");

  const grouped = items.reduce<Record<string, QuoteItem[]>>((acc, item) => {
    (acc[item.category] ??= []).push(item);
    return acc;
  }, {});

  const expired =
    quote.status === "expired" ||
    (quote.valid_until ? new Date(quote.valid_until) < new Date() : false);
  const actionable = !expired && (quote.status === "sent" || quote.status === "viewed");

  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-10">
      <header className="border-b border-slate-200 pb-6">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-slate-400">
              Quote {quote.quote_number}
            </p>
            <h1 className="mt-1 text-3xl font-bold tracking-tight">
              {contractor.company_name}
            </h1>
            {address && <p className="mt-1 text-sm text-slate-600">{address}</p>}
            {customer.contact_name && (
              <p className="text-sm text-slate-600">Prepared for {customer.contact_name}</p>
            )}
          </div>
          <span
            className={`rounded-full px-3 py-1 text-xs font-semibold uppercase tracking-wide ${
              quote.status === "accepted"
                ? "bg-emerald-100 text-emerald-800"
                : expired
                  ? "bg-slate-200 text-slate-600"
                  : "bg-blue-100 text-blue-800"
            }`}
          >
            {expired && quote.status !== "declined" ? "expired" : quote.status}
          </span>
        </div>
      </header>

      {expired && (
        <p className="mt-6 rounded-lg bg-amber-50 px-4 py-3 text-sm text-amber-800">
          This quote expired on{" "}
          {quote.valid_until ? new Date(quote.valid_until).toLocaleDateString() : "its validity date"}
          . Contact {contractor.company_name} to have it reissued.
        </p>
      )}

      <section className="mt-8">
        <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
          Scope and pricing
        </h2>
        <div className="mt-3 space-y-6">
          {Object.entries(grouped).map(([category, list]) => (
            <div key={category}>
              <h3 className="text-sm font-semibold text-slate-700">
                {CATEGORY_LABELS[category] ?? category}
              </h3>
              <div className="mt-2 overflow-hidden rounded-xl border border-slate-200">
                <table className="w-full text-sm">
                  <tbody className="divide-y divide-slate-100">
                    {list.map((item, i) => (
                      <tr key={`${item.code}-${i}`} className="align-top">
                        <td className="px-4 py-3">
                          <p className="font-medium">{item.label}</p>
                          {item.description && (
                            <p className="mt-0.5 text-xs text-slate-500">
                              {item.description}
                            </p>
                          )}
                        </td>
                        <td className="whitespace-nowrap px-4 py-3 text-right text-xs text-slate-500">
                          {Number(item.quantity).toLocaleString()} {item.unit} ×{" "}
                          {money(item.unit_price, currency)}
                        </td>
                        <td className="whitespace-nowrap px-4 py-3 text-right tabular-nums font-medium">
                          {money(item.line_total, currency)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="mt-8 flex justify-end">
        <dl className="w-full max-w-sm space-y-1.5 text-sm">
          <Row label="Subtotal" value={money(quote.subtotal, currency)} />
          {Number(quote.contingency_total) > 0 && (
            <Row label="Contingency" value={money(quote.contingency_total, currency)} />
          )}
          <Row label="Overhead" value={money(quote.overhead_total, currency)} />
          <Row label="Profit" value={money(quote.profit_total, currency)} />
          {Number(quote.tax_total) > 0 && (
            <Row label="Tax" value={money(quote.tax_total, currency)} />
          )}
          {Number(quote.min_charge_adjustment) > 0 && (
            <Row
              label="Minimum charge adjustment"
              value={money(quote.min_charge_adjustment, currency)}
            />
          )}
          <div className="flex justify-between border-t border-slate-300 pt-2 text-base font-bold">
            <dt>Total</dt>
            <dd className="tabular-nums">{money(quote.total, currency)}</dd>
          </div>
          {Number(quote.price_per_sqft) > 0 && (
            <div className="flex justify-between text-xs text-slate-500">
              <dt>Per square foot</dt>
              <dd className="tabular-nums">
                {money(quote.price_per_sqft, currency)}
              </dd>
            </div>
          )}
          <div className="flex justify-between text-sm font-semibold text-emerald-800">
            <dt>Deposit due</dt>
            <dd className="tabular-nums">{money(quote.deposit_amount, currency)}</dd>
          </div>
        </dl>
      </section>

      {Array.isArray(quote.warnings) && quote.warnings.length > 0 && (
        <section className="mt-8">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Worth knowing
          </h2>
          <ul className="mt-2 space-y-1.5 text-sm text-slate-600">
            {quote.warnings.map((w, i) => (
              <li key={i} className="flex gap-2">
                <span aria-hidden className="text-amber-500">
                  •
                </span>
                {w}
              </li>
            ))}
          </ul>
        </section>
      )}

      {quote.ai_scope_of_work && (
        <section className="mt-8">
          <h2 className="text-sm font-semibold uppercase tracking-wide text-slate-500">
            Scope of work
          </h2>
          <div className="mt-2 whitespace-pre-wrap rounded-xl border border-slate-200 bg-white p-4 text-sm leading-relaxed text-slate-700">
            {quote.ai_scope_of_work}
          </div>
          <p className="mt-1.5 text-xs text-slate-400">
            Drafted automatically from your answers and reviewed before it is
            issued. It is a description of work, not a contract.
          </p>
        </section>
      )}

      {actionable && (
        <QuoteDecision
          quoteToken={quoteToken}
          status={quote.status}
          total={money(quote.total, currency)}
        />
      )}

      {(contractor.terms || contractor.phone) && (
        <footer className="mt-10 border-t border-slate-200 pt-6 text-xs text-slate-500">
          {contractor.terms && (
            <p className="whitespace-pre-wrap leading-relaxed">{contractor.terms}</p>
          )}
          <p className="mt-3">
            {contractor.company_name}
            {contractor.license_no && ` · Lic ${contractor.license_no}`}
            {contractor.phone && ` · ${contractor.phone}`}
            {contractor.website && (
              <>
                {" · "}
                <a href={contractor.website} className="underline">
                  {contractor.website}
                </a>
              </>
            )}
          </p>
          <p className="mt-1">
            Quote valid until{" "}
            {quote.valid_until ? new Date(quote.valid_until).toLocaleDateString() : "—"}
            {contractor.warranty_years
              ? ` · ${contractor.warranty_years} year workmanship warranty`
              : ""}
          </p>
        </footer>
      )}
    </main>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between">
      <dt className="text-slate-600">{label}</dt>
      <dd className="tabular-nums">{value}</dd>
    </div>
  );
}
