import { createClient } from "@/lib/supabase/server";
import { callRpc as call } from "@/lib/rq/transport";
import type {
  DashboardStats,
  StaffLead,
  StaffListResult,
  StaffPreview,
  StaffQuestion,
  StaffQuote,
  StaffQuoteDetail,
  StaffRateItem,
} from "@/lib/rq/types";

/**
 * Staff RPCs. Every one of these resolves the caller's contractor from the
 * session via rq_my_contractor_id() inside the database, so there is no
 * contractor id to pass in and no way to address another tenant's rows.
 *
 * callRpc retries transient transport failures; see lib/rq/transport.ts.
 */
export async function bootstrap(): Promise<unknown> {
  const supabase = await createClient();
  return call(
    () => supabase.rpc("rq_staff_bootstrap" as never, {} as never),
    "rq_staff_bootstrap",
  );
}

export async function dashboardStats(): Promise<DashboardStats> {
  const supabase = await createClient();
  return call<DashboardStats>(
    () => supabase.rpc("rq_staff_dashboard_stats" as never, {} as never),
    "rq_staff_dashboard_stats",
  );
}

export async function listLeads(opts?: {
  status?: string;
  search?: string;
  limit?: number;
  offset?: number;
}): Promise<StaffListResult<StaffLead>> {
  const supabase = await createClient();
  return call<StaffListResult<StaffLead>>(
    () =>
      supabase.rpc("rq_staff_list_leads" as never, {
        p_status: opts?.status ?? null,
        p_search: opts?.search ?? null,
        p_limit: opts?.limit ?? 50,
        p_offset: opts?.offset ?? 0,
      } as never),
    "rq_staff_list_leads",
  );
}

export async function listQuotes(opts?: {
  status?: string;
  search?: string;
  limit?: number;
  offset?: number;
}): Promise<StaffListResult<StaffQuote>> {
  const supabase = await createClient();
  return call<StaffListResult<StaffQuote>>(
    () =>
      supabase.rpc("rq_staff_list_quotes" as never, {
        p_status: opts?.status ?? null,
        p_search: opts?.search ?? null,
        p_limit: opts?.limit ?? 50,
        p_offset: opts?.offset ?? 0,
      } as never),
    "rq_staff_list_quotes",
  );
}

export async function getQuote(quoteId: string): Promise<StaffQuoteDetail> {
  const supabase = await createClient();
  return call<StaffQuoteDetail>(
    () => supabase.rpc("rq_staff_get_quote" as never, { p_quote_id: quoteId } as never),
    "rq_staff_get_quote",
  );
}

export async function staffPreview(answers: Record<string, unknown>): Promise<StaffPreview> {
  const supabase = await createClient();
  return call<StaffPreview>(
    () => supabase.rpc("rq_preview_quote_for_staff" as never, { p_answers: answers } as never),
    "rq_preview_quote_for_staff",
  );
}

/** Effective rate card: system defaults with this contractor's overrides applied. */
export async function listRateItems(): Promise<StaffRateItem[]> {
  const supabase = await createClient();
  return call<StaffRateItem[]>(
    () => supabase.rpc("rq_staff_list_rate_items" as never, {} as never),
    "rq_staff_list_rate_items",
  );
}

/** Effective questionnaire, same override semantics as the rate card. */
export async function listQuestions(): Promise<StaffQuestion[]> {
  const supabase = await createClient();
  return call<StaffQuestion[]>(
    () => supabase.rpc("rq_staff_list_questions" as never, {} as never),
    "rq_staff_list_questions",
  );
}

export async function saveSettings(settings: Record<string, unknown>): Promise<unknown> {
  const supabase = await createClient();
  return call(
    () => supabase.rpc("rq_staff_save_settings" as never, { p_settings: settings } as never),
    "rq_staff_save_settings",
  );
}

/**
 * rq_staff_save_settings is a partial update that returns the whole row, so an
 * empty object is a no-op write that doubles as the settings read.
 */
export async function getSettings(): Promise<Record<string, unknown>> {
  const supabase = await createClient();
  return call<Record<string, unknown>>(
    () => supabase.rpc("rq_staff_save_settings" as never, { p_settings: {} } as never),
    "rq_staff_save_settings",
  );
}

export async function saveRateItem(item: Record<string, unknown>): Promise<unknown> {
  const supabase = await createClient();
  return call(
    () => supabase.rpc("rq_staff_save_rate_item" as never, { p_item: item } as never),
    "rq_staff_save_rate_item",
  );
}

export async function saveQuestion(question: Record<string, unknown>): Promise<unknown> {
  const supabase = await createClient();
  return call(
    () => supabase.rpc("rq_staff_save_question" as never, { p_question: question } as never),
    "rq_staff_save_question",
  );
}

export async function resetRateItems(): Promise<unknown> {
  const supabase = await createClient();
  return call(
    () => supabase.rpc("rq_staff_reset_rate_items" as never, {} as never),
    "rq_staff_reset_rate_items",
  );
}

export async function setLeadStatus(leadId: string, status: string): Promise<unknown> {
  const supabase = await createClient();
  return call(
    () =>
      supabase.rpc("rq_staff_set_lead_status" as never, { p_lead_id: leadId, p_status: status } as never),
    "rq_staff_set_lead_status",
  );
}

export async function setQuoteStatus(quoteId: string, status: string): Promise<unknown> {
  const supabase = await createClient();
  return call(
    () =>
      supabase.rpc("rq_staff_set_quote_status" as never, {
        p_quote_id: quoteId,
        p_status: status,
      } as never),
    "rq_staff_set_quote_status",
  );
}

export async function regenerateQuote(leadId: string): Promise<unknown> {
  const supabase = await createClient();
  return call(
    () => supabase.rpc("rq_staff_regenerate_quote" as never, { p_lead_id: leadId } as never),
    "rq_staff_regenerate_quote",
  );
}
