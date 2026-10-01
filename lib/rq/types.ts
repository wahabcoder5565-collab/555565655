/**
 * Shapes returned by the rq_ PostgREST RPCs.
 *
 * These mirror the SQL exactly rather than the underlying tables, because the
 * public RPCs deliberately project away anything commercially sensitive:
 * rq_public_config never returns unit_price or markup, and rq_preview_quote
 * returns only headline figures. Do not widen these types to match the tables.
 */

export type Contractor = {
  company_name: string;
  phone: string;
  website: string;
  license_no: string;
  city: string;
  state: string;
  brand_color: string;
  warranty_years: number;
  currency: string;
};

export type QuestionInputType =
  | "text"
  | "textarea"
  | "number"
  | "select"
  | "radio"
  | "checkbox"
  | "boolean"
  | (string & {});

/**
 * rq_questions.options is a jsonb array of plain strings, e.g.
 * ["none","felt","synthetic"] — the stored value and the label are the same
 * thing. The RPCs return the column untouched, so this is string[] on the wire.
 */
export type QuestionOption = string;

export type Question = {
  key: string;
  section: string;
  label: string;
  help_text: string;
  input_type: QuestionInputType;
  unit: string;
  options: QuestionOption[];
  required: boolean;
  min_value: number | null;
  max_value: number | null;
  step_value: number | null;
  sort_order: number;
};

/** rq_public_config(). contractor is null until the first staff signup. */
export type PublicConfig = {
  contractor: Contractor | null;
  questions: Question[];
};

/** Coarse, anonymous-safe estimate. No line items, no markup. */
export type PublicPreview = {
  roof_area_sqft: number;
  area_source: string;
  estimated_total: number;
  deposit_amount: number;
  price_per_sqft: number;
  currency: string;
  is_placeholder: boolean;
};

/**
 * rq_coerce_answers produces JSON null for a blank text answer, a scalar for
 * number/select/boolean, and an array for multi_select, so arrays belong here.
 */
export type AnswerValue = string | number | boolean | null | string[] | number[];

export type Answers = Record<string, AnswerValue>;

export type Contact = {
  name?: string;
  email?: string;
  phone?: string;
};

/** rq_public_start_lead() */
export type StartLeadResult = {
  token: string;
};

/**
 * rq_public_lead(). The SQL nests contact fields under `contact` with
 * `contact_`-prefixed keys, and exposes progress as `current_step` and a
 * `completion` percentage.
 */
export type PublicLead = {
  token: string;
  status: string;
  answers: Answers;
  contact: {
    contact_name: string;
    contact_email: string;
    contact_phone: string;
  };
  current_step: number;
  completion: number;
  contractor: {
    company_name: string;
    brand_color: string;
  };
};

/** rq_public_save() */
export type SaveResult = {
  ok: boolean;
  answered: number;
  completion: number;
  active_questions: number;
};

/**
 * rq_public_submit(). A validation failure comes back with ok=false and the
 * missing keys rather than an exception, so the wizard can highlight them.
 */
export type SubmitResult = {
  ok: boolean;
  error?: string;
  missing?: string[];
  quote_id?: string;
  quote_token?: string;
  quote_number?: string;
};

export type QuoteItem = {
  category: string;
  code: string;
  label: string;
  description: string;
  quantity: number;
  unit: string;
  unit_price: number;
  line_total: number;
  sort_order?: number;
};

export type QuoteTotals = {
  subtotal: number;
  contingency_total: number;
  overhead_total: number;
  profit_total: number;
  tax_total: number;
  min_charge_adjustment: number;
  total: number;
  deposit_amount: number;
  price_per_sqft: number;
};

/**
 * rq_public_quote(). The quote row is projected with `answers`, `pricing` and
 * `notes` stripped from it, but `pricing` still comes back as a sibling key and
 * carries the contractor's markup percentages.
 */
export type PublicQuote = {
  quote: {
    id: string;
    quote_number: string;
    status: string;
    project_type: string;
    roof_area_sqft: number;
    subtotal: number;
    contingency_total: number;
    overhead_total: number;
    profit_total: number;
    tax_total: number;
    min_charge_adjustment: number;
    total: number;
    deposit_amount: number;
    price_per_sqft: number;
    warnings: string[] | null;
    valid_until: string;
    created_at: string;
    viewed_at: string | null;
    responded_at: string | null;
    ai_scope_of_work: string | null;
    ai_status: string;
  };
  answers: Answers;
  pricing: Record<string, number | string>;
  items: QuoteItem[];
  customer: {
    contact_name: string;
    contact_email: string;
    contact_phone: string;
    property_address: string;
    property_city: string;
    property_state: string;
    property_zip: string;
  };
  contractor: {
    company_name: string;
    phone: string;
    website: string;
    license_no: string;
    address_line: string;
    city: string;
    state: string;
    zip_code: string;
    logo_url: string;
    brand_color: string;
    terms: string;
    warranty_years: number;
  };
};

export type RespondResult = {
  ok: boolean;
  status: string;
};

/* ------------------------------- staff surface ---------------------------- */

/** rq_staff_dashboard_stats() */
export type DashboardStats = {
  leads_total: number;
  leads_open: number;
  leads_30d: number;
  leads_by_status: Record<string, number>;
  quotes_total: number;
  quotes_by_status: Record<string, number>;
  pipeline_value: number;
  won_value: number;
  average_quote: number;
  win_rate: number;
  ai_pending: number;
  ai_failed: number;
};

export type StaffRateItem = {
  id: string;
  code: string;
  category: string;
  label: string;
  description: string;
  unit: string;
  unit_cost: number;
  unit_price: number;
  sort_order: number;
  is_active: boolean;
  is_override: boolean;
};

export type StaffQuestion = {
  id: string;
  key: string;
  section: string;
  label: string;
  help_text: string;
  input_type: string;
  unit: string;
  options: QuestionOption[];
  required: boolean;
  affects_price: boolean;
  min_value: number | null;
  max_value: number | null;
  step_value: number | null;
  sort_order: number;
  is_active: boolean;
  is_override: boolean;
};

/** Full itemised preview. Staff only; never exposed anonymously. */export type StaffPreview = {
  inputs: Record<string, string | number | boolean>;
  items: QuoteItem[];
  totals: QuoteTotals;
  pricing: Record<string, number | string>;
  warnings: string[];
  contractor: Contractor;
};

/**
 * rq_staff_list_leads / rq_staff_list_quotes return a paging envelope, not a
 * bare array: { rows: [...], total }. Confirmed with jsonb_typeof against the
 * live database.
 */
export type StaffListResult<T> = {
  rows: T[];
  total: number;
};

/** Row shape of rq_staff_list_leads -> rows[]. */
export type StaffLead = {
  id: string;
  public_token: string;
  status: string;
  contact_name: string;
  contact_email: string;
  contact_phone: string;
  property_address: string;
  property_city: string;
  property_state: string;
  property_zip: string;
  project_type: string;
  completion: number | null;
  utm_source: string | null;
  utm_campaign: string | null;
  created_at: string;
  submitted_at: string | null;
  quote_count: number;
  latest_quote_id: string | null;
  latest_quote_number: string | null;
  latest_quote_total: number | null;
  latest_quote_status: string | null;
};

/** Row shape of rq_staff_list_quotes -> rows[]. */
export type StaffQuote = {
  id: string;
  public_token: string;
  quote_number: string;
  status: string;
  project_type: string;
  roof_area_sqft: number | null;
  total: number;
  deposit_amount: number;
  price_per_sqft: number | null;
  ai_status: string | null;
  created_at: string;
  viewed_at: string | null;
  responded_at: string | null;
  valid_until: string;
  lead_id: string;
  contact_name: string;
  property_address: string;
  property_city: string;
  property_state: string;
  property_zip: string;
};

/**
 * rq_staff_get_quote returns { quote, lead, items, events, public_url_token }.
 * `quote` is the full rq_quotes row minus public_token, so the money columns are
 * authoritative and must be read from here rather than recomputed.
 */
export type StaffQuoteDetail = {
  quote: {
    id: string;
    quote_number: string;
    lead_id: string;
    status: string;
    project_type: string;
    roof_area_sqft: number | null;
    subtotal: number;
    total: number;
    deposit_amount: number;
    price_per_sqft: number | null;
    valid_until: string;
    created_at: string;
    viewed_at: string | null;
    responded_at: string | null;
    ai_status: string | null;
    ai_scope_of_work: string | null;
    ai_summary: string | null;
    ai_recommendations: unknown;
    ai_risk_notes: unknown;
    ai_engine: string | null;
    ai_model: string | null;
    ai_error: string | null;
  };
  lead: StaffLead | null;
  items: QuoteItem[];
  events: Array<{
    id: string;
    action: string;
    detail: string;
    actor_role: string;
    created_at: string;
  }>;
  public_url_token: string;
};