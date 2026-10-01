import Link from "next/link";
import { getPublicConfig } from "@/lib/rq/public";
import type { Contractor, PublicConfig } from "@/lib/rq/types";
import { StartQuoteButton } from "@/components/start-quote-button";

/**
 * Wordmark fallback when the contractor has not set a company name yet.
 */
function identity(contractor: Contractor | null) {
  return {
    name: contractor?.company_name?.trim() || "Roof Quote",
    place: [contractor?.city, contractor?.state].filter(Boolean).join(", "),
  };
}

/**
 * The hero's accent is the contractor's own brand colour, but only if it parses as
 * a hex value. brand_color is free text on settings and is interpolated into
 * style, so an unparseable value would produce an invalid style and an unstyled
 * hero rather than an error. Anything not matching is ignored on purpose.
 */
function accent(contractor: Contractor | null): string | null {
  const raw = contractor?.brand_color?.trim() ?? "";
  return /^#[0-9a-fA-F]{6}$/.test(raw) ? raw : null;
}

const TRUST_POINTS = [
  {
    title: "Itemised, not a range",
    body: "Every line is priced off a rate card you control, so the numbers add up in front of the customer.",
  },
  {
    title: "Written scope of work",
    body: "A plain-English description of the job, generated for the roof that was actually described.",
  },
  {
    title: "No obligation",
    body: "Nothing is charged and no address is required until you ask for a site visit.",
  },
];

export default async function HomePage() {
  // The public homepage must not turn a momentary network blip into a 500 with a
  // stack trace in front of a prospective customer. A failed config read renders
  // an honest unavailable state; the server log keeps the real cause.
  let config: PublicConfig;
  try {
    config = await getPublicConfig();
  } catch (err) {
    console.error("home: rq_public_config failed", err);
    return (
      <main className="flex-1">
        <div className="mx-auto w-full max-w-3xl px-6 py-16">
          <h1 className="text-3xl font-bold tracking-tight">
            We are having trouble reaching the quote service
          </h1>
          <p className="mt-4 text-slate-600">
            This is temporary. Please refresh in a moment, or try again shortly.
          </p>
        </div>
      </main>
    );
  }

  const contractor = config.contractor;
  const { name, place } = identity(contractor);
  const brand = accent(contractor);

  return (
    <main className="flex-1">
      {/* Hero. Light theme: a white base with a faint brand wash, so the page
          matches the white body behind it instead of banding at the fold. */}
      <section className="relative overflow-hidden border-b border-slate-200 bg-white">
        {/* Brand wash. Two soft radial pools rather than a photograph: nothing
            to download, no licence to track, and it re-tints when the contractor
            changes their brand colour. Alpha is kept low so headline text stays
            above the WCAG AA contrast floor on white. */}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0"
          style={{
            background: brand
              ? `radial-gradient(110% 80% at 12% -10%, ${brand}1f 0%, transparent 55%), radial-gradient(80% 70% at 100% 110%, ${brand}14 0%, transparent 60%)`
              : "radial-gradient(110% 80% at 12% -10%, #0f766e1f 0%, transparent 55%)",
          }}
        />

        <div className="relative mx-auto w-full max-w-5xl px-6 py-20 sm:py-28">
          {place && (
            <p className="text-sm font-semibold uppercase tracking-widest text-teal-700">
              {place}
            </p>
          )}

          <h1 className="mt-4 max-w-3xl text-4xl font-bold tracking-tight text-slate-900 sm:text-6xl">
            {contractor?.company_name?.trim()
              ? `${name} roof quotes`
              : "Get an itemised roof quote in minutes"}
          </h1>

          <p className="mt-6 max-w-2xl text-lg leading-relaxed text-slate-600 sm:text-xl">
            Answer a short set of questions about your roof and get a line-by-line
            estimate with a written scope of work. No guesswork, no vague ballpark,
            no obligation.
          </p>

          <div className="mt-9 max-w-md">
            {contractor ? (
              <StartQuoteButton />
            ) : (
              <p className="rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
                Quoting opens once a contractor account is set up.
              </p>
            )}
            <p className="mt-3 text-xs text-slate-500">
              Takes about two minutes. You can stop and come back.
            </p>
          </div>
        </div>
      </section>

      {/* Why it is different */}
      <section className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20">
        <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
          A quote you can actually read
        </h2>
        <p className="mt-3 max-w-2xl text-slate-600">
          Most roofing estimates are a single number on a page. This one shows
          every line that makes it up.
        </p>

        <dl className="mt-10 grid gap-8 sm:grid-cols-3">
          {TRUST_POINTS.map((point) => (
            <div key={point.title}>
              <dt className="font-semibold">{point.title}</dt>
              <dd className="mt-2 text-sm leading-relaxed text-slate-600">
                {point.body}
              </dd>
            </div>
          ))}
        </dl>
      </section>

      {/* How it works */}
      <section className="border-y border-slate-200 bg-slate-50">
        <div className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20">
          <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
            Three steps, no paperwork
          </h2>
          <ol className="mt-10 grid gap-8 sm:grid-cols-3">
            {[
              {
                step: "1",
                title: "Describe the roof",
                body: "Area, pitch, material, how many layers are up there.",
              },
              {
                step: "2",
                title: "Get the breakdown",
                body: "Itemised lines priced from the contractor's own rate card.",
              },
              {
                step: "3",
                title: "Read the scope",
                body: "A written description of the work, then accept or decline.",
              },
            ].map((item) => (
              <li key={item.step} className="flex gap-4">
                <span
                  aria-hidden
                  className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-slate-900 text-sm font-semibold text-white"
                >
                  {item.step}
                </span>
                <div>
                  <p className="font-semibold">{item.title}</p>
                  <p className="mt-2 text-sm leading-relaxed text-slate-600">
                    {item.body}
                  </p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      {/* Details and call to action */}
      <section className="mx-auto w-full max-w-5xl px-6 py-16 sm:py-20">
        <div className="grid gap-10 lg:grid-cols-[1.4fr_1fr]">
          <div>
            <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">
              {contractor ? `Why use ${name}` : "How these estimates are built"}
            </h2>
            <p className="mt-4 text-slate-600">
              Every total is computed from a fixed rate card held by the
              contractor, not estimated by a model. The same roof and the same
              answers always produce the same price.
            </p>
            <p className="mt-4 text-sm text-slate-500">
              Estimates are produced from a fixed rate card and are not a binding
              offer until confirmed on site.
            </p>
          </div>

          <aside className="rounded-xl border border-slate-200 bg-white p-6 shadow-sm">
            {contractor ? (
              <dl className="space-y-4 text-sm">
                {contractor.warranty_years > 0 && (
                  <div>
                    <dt className="text-slate-500">Workmanship warranty</dt>
                    <dd className="font-medium">{contractor.warranty_years} years</dd>
                  </div>
                )}
                {contractor.license_no && (
                  <div>
                    <dt className="text-slate-500">Licence</dt>
                    <dd className="font-medium">{contractor.license_no}</dd>
                  </div>
                )}
                {contractor.phone && (
                  <div>
                    <dt className="text-slate-500">Phone</dt>
                    <dd className="font-medium">{contractor.phone}</dd>
                  </div>
                )}
                {contractor.website && (
                  <div>
                    <dt className="text-slate-500">Website</dt>
                    <dd className="font-medium break-all">{contractor.website}</dd>
                  </div>
                )}
              </dl>
            ) : (
              <div className="text-sm text-amber-900">
                <h3 className="font-semibold">No contractor configured yet</h3>
                <p className="mt-2">
                  The engine reads its rate card from a contractor record, and the
                  database has none yet. The first genuine staff signup creates the
                  primary contractor automatically, after which this page becomes a
                  working estimator.
                </p>
              </div>
            )}

            <Link
              href="/staff/login"
              className="mt-6 inline-block rounded-lg bg-slate-900 px-4 py-2 text-sm font-medium text-white transition hover:bg-slate-800"
            >
              Contractor sign in
            </Link>
          </aside>
        </div>
      </section>
    </main>
  );
}