/**
 * Deterministic scope-of-work writer.
 *
 * This is the baseline that always runs, with or without an LLM configured. It
 * derives prose from the answers and the priced line items, so a quote can never
 * be left without a description of work.
 *
 * The important invariant: nothing in this file computes or invents a price.
 * Every figure it prints is copied from a line item or total that Postgres
 * already produced, and it is copied as a formatted string, never re-derived.
 */

export type Draft = {
  scope_of_work: string;
  summary: string;
  recommendations: string[];
  risk_notes: string[];
};

export type QuoteInput = {
  quoteNumber: string;
  projectType: string;
  roofAreaSqft: number;
  warrantyYears: number;
  answers: Record<string, unknown>;
  items: {
    category: string;
    label: string;
    description: string;
    quantity: number;
    unit: string;
    lineTotal: number;
  }[];
  total: number;
  depositAmount: number;
  currency: string;
  validUntil: string;
  warnings: string[] | null;
};

const money = (v: number, currency: string) =>
  new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: currency || "USD",
    maximumFractionDigits: 0,
  }).format(Number(v));

const CATEGORY_HEADINGS: Record<string, string> = {
  material: "Materials",
  underlayment: "Underlayment and protection",
  accessory: "Accessories",
  teardown: "Teardown",
  disposal: "Debris removal",
  labor: "Labour",
  permit: "Permits and inspections",
};

const text = (answers: Record<string, unknown>, key: string): string => {
  const v = answers[key];
  if (v === null || v === undefined) return "";
  if (Array.isArray(v)) return v.map(String).join(", ");
  return String(v);
};

export function buildDeterministicDraft(input: QuoteInput): Draft {
  const { answers, items } = input;

  const address = [
    text(answers, "property_address"),
    [text(answers, "property_city"), text(answers, "property_state")]
      .filter(Boolean)
      .join(", "),
  ]
    .filter(Boolean)
    .join(", ");

  const layers = text(answers, "roof_layers") || text(answers, "roof_material");
  const pitch = text(answers, "roof_pitch") || text(answers, "roof_stories");
  const tearOff = text(answers, "tear_off") || text(answers, "existing_roof");

  const opening: string[] = [];
  opening.push(
    `This scope covers a ${input.projectType} roofing project${
      address ? ` at ${address}` : ""
    }.`,
  );
  if (Number(input.roofAreaSqft) > 0) {
    opening.push(
      `The roof area used for pricing is ${Number(
        input.roofAreaSqft,
      ).toLocaleString()} square feet.`,
    );
  }
  if (layers) opening.push(`The existing roof is described as ${layers}.`);
  if (pitch) opening.push(`Access and pitch considerations: ${pitch}.`);
  if (tearOff) opening.push(`Tear-off condition: ${tearOff}.`);

  // Group the priced lines so the reader sees the same structure the invoice
  // will have, in the same order Postgres produced.
  const grouped = items.reduce<Record<string, QuoteInput["items"]>>((acc, item) => {
    (acc[item.category] ??= []).push(item);
    return acc;
  }, {});

  const body: string[] = [];
  for (const [category, list] of Object.entries(grouped)) {
    const heading = CATEGORY_HEADINGS[category] ?? category;
    const rendered = list
      .map((item) => {
        const qty = `${Number(item.quantity).toLocaleString()} ${item.unit}`;
        const desc = item.description ? ` (${item.description})` : "";
        return `  - ${item.label}${desc}: ${qty} at ${money(
          item.lineTotal,
          input.currency,
        )}`;
      })
      .join("\n");
    body.push(`${heading}\n${rendered}`);
  }

  const closing = [
    `Total installed price: ${money(input.total, input.currency)}.`,
    `Deposit to schedule: ${money(input.depositAmount, input.currency)}.`,
    input.warrantyYears > 0
      ? `Workmanship warranty: ${input.warrantyYears} years.`
      : "",
    `This quote is valid until ${input.validUntil || "the date shown above"}.`,
  ]
    .filter(Boolean)
    .join(" ");

  const recommendations: string[] = [];
  if (Number(input.roofAreaSqft) > 0 && Number(input.roofAreaSqft) < 800) {
    recommendations.push(
      "This is a small area, so mobilisation and disposal costs are a large share of the total. Confirm access before booking crew.",
    );
  }
  if (text(answers, "roof_age")) {
    recommendations.push(
      "Given the age of the existing roof, budget for decking repairs once the old material is removed. Those are priced separately if found.",
    );
  }
  if (!text(answers, "property_state") && !text(answers, "property_city")) {
    recommendations.push(
      "We do not have a service address on file yet, which can affect permit requirements. Please confirm it before we schedule.",
    );
  }
  if (recommendations.length === 0) {
    recommendations.push(
      "Nothing unusual was flagged in the answers. A site visit before work starts will confirm the quantities above.",
    );
  }

  const riskNotes: string[] = [];
  for (const w of input.warnings ?? []) riskNotes.push(w);
  if (riskNotes.length === 0) {
    riskNotes.push(
      "Quantities are derived from the answers provided, not a measured survey. Final material take-off may vary.",
    );
  }

  return {
    scope_of_work: [...opening, "", ...body, "", closing].join("\n"),
    summary: [
      `${input.projectType} roofing work`,
      Number(input.roofAreaSqft) > 0
        ? `${Number(input.roofAreaSqft).toLocaleString()} sq ft`
        : null,
      `${items.length} line items`,
      money(input.total, input.currency),
    ]
      .filter(Boolean)
      .join(" · "),
    recommendations,
    risk_notes: riskNotes.slice(0, 6),
  };
}
