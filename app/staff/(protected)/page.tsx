import { bootstrap, dashboardStats } from "@/lib/rq/staff";

const MONEY = new Intl.NumberFormat("en-US", {
  style: "currency",
  currency: "USD",
  maximumFractionDigits: 0,
});

export default async function StaffDashboardPage() {
  // Ensures the contractor exists and the session's rate card is materialised.
  await bootstrap();
  const stats = await dashboardStats();

  const cards = [
    { label: "Open leads", value: stats.leads_open, sub: `${stats.leads_30d} in last 30d` },
    { label: "Quotes", value: stats.quotes_total, sub: `${stats.quotes_by_status.sent ?? 0} sent` },
    { label: "Pipeline", value: MONEY.format(stats.pipeline_value), sub: "sent + viewed" },
    { label: "Won", value: MONEY.format(stats.won_value), sub: `${stats.win_rate}% win rate` },
    { label: "Average quote", value: MONEY.format(stats.average_quote), sub: "sent, viewed, accepted" },
    { label: "Total leads", value: stats.leads_total, sub: "all time" },
  ];

  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Dashboard</h1>

      {stats.ai_failed > 0 ? (
        <p className="mt-4 rounded-lg bg-red-50 px-4 py-3 text-sm text-red-700">
          {stats.ai_failed} quote(s) failed AI generation. Open them to retry.
        </p>
      ) : null}

      <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {cards.map((card) => (
          <div
            key={card.label}
            className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm"
          >
            <p className="text-sm text-slate-500">{card.label}</p>
            <p className="mt-1 text-2xl font-semibold tabular-nums">{card.value}</p>
            <p className="mt-1 text-xs text-slate-400">{card.sub}</p>
          </div>
        ))}
      </div>

      <section className="mt-8 grid gap-4 sm:grid-cols-2">
        <div className="rounded-xl border border-slate-200 bg-white p-5">
          <h2 className="text-sm font-semibold text-slate-700">Leads by status</h2>
          <StatusList counts={stats.leads_by_status} />
        </div>
        <div className="rounded-xl border border-slate-200 bg-white p-5">
          <h2 className="text-sm font-semibold text-slate-700">Quotes by status</h2>
          <StatusList counts={stats.quotes_by_status} />
        </div>
      </section>
    </div>
  );
}

function StatusList({ counts }: { counts: Record<string, number> }) {
  const entries = Object.entries(counts ?? {}).sort((a, b) => b[1] - a[1]);
  if (entries.length === 0) {
    return <p className="mt-3 text-sm text-slate-400">Nothing yet.</p>;
  }
  return (
    <ul className="mt-3 space-y-1.5">
      {entries.map(([status, n]) => (
        <li key={status} className="flex justify-between text-sm">
          <span className="text-slate-600">{status.replace(/_/g, " ")}</span>
          <span className="font-medium tabular-nums">{n}</span>
        </li>
      ))}
    </ul>
  );
}
