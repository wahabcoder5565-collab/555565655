import type { Metadata } from "next";
import { getLead, getPublicConfig } from "@/lib/rq/public";
import { QuoteWizard } from "@/components/quote-wizard";

export const metadata: Metadata = { title: "Your roof quote" };

type Props = {
  params: Promise<{ token: string }>;
};

export default async function QuoteWizardPage({ params }: Props) {
  const { token } = await params;

  // An unknown or already-submitted token should not be distinguishable from
  // the customer's point of view, so both land on the same notFound page.
  const [lead, config] = await Promise.all([
    getLead(token).catch(() => null),
    getPublicConfig().catch(() => null),
  ]);

  if (!lead || !config) {
    return (
      <main className="mx-auto max-w-lg px-6 py-24 text-center">
        <h1 className="text-2xl font-bold tracking-tight">This link is not valid</h1>
        <p className="mt-3 text-sm text-slate-600">
          The quote link may have expired or been mistyped. Start a new quote from
          the home page and we will pick up where you left off.
        </p>
      </main>
    );
  }

  if (lead.status !== "draft") {
    return (
      <main className="mx-auto max-w-lg px-6 py-24 text-center">
        <h1 className="text-2xl font-bold tracking-tight">Already submitted</h1>
        <p className="mt-3 text-sm text-slate-600">
          This request has already been priced. Check the email address you gave
          us for the quote, or contact {lead.contractor.company_name} directly and
          we will resend it.
        </p>
      </main>
    );
  }

  return (
    <main>
      <QuoteWizard
        token={lead.token}
        lead={lead}
        questions={config.questions}
      />
    </main>
  );
}
