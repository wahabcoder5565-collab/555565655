"use server";

import { revalidatePath } from "next/cache";
import {
  resetRateItems,
  saveQuestion,
  saveRateItem,
  saveSettings,
  setLeadStatus,
  setQuoteStatus,
  regenerateQuote,
} from "@/lib/rq/staff";

import type { ActionState as FormState } from "@/lib/rq/action-state";

export type { FormState };

function err(e: unknown, fallback: string): FormState {
  return { ok: false, message: e instanceof Error ? e.message : fallback };
}

/**
 * These actions are called from Client Components, so a return value is needed
 * for feedback; a thrown error would surface as an opaque digest.
 */

export async function saveSettingsAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const keys = [
    "company_name",
    "contact_email",
    "phone",
    "license_no",
    "website",
    "address_line",
    "city",
    "state",
    "zip_code",
    "currency",
    "logo_url",
    "terms",
    "brand_color",
  ];
  const numbers = [
    "waste_factor_pct",
    "overhead_pct",
    "profit_pct",
    "contingency_pct",
    "tax_pct",
    "min_charge",
    "deposit_pct",
    "valid_days",
    "warranty_years",
  ];

  const payload: Record<string, unknown> = {};
  for (const key of keys) {
    const raw = formData.get(key);
    if (raw !== null) payload[key] = String(raw);
  }
  for (const key of numbers) {
    const raw = formData.get(key);
    if (raw === null || String(raw).trim() === "") continue;
    const n = Number(raw);
    if (Number.isNaN(n)) {
      return { ok: false, message: `${key} must be a number.` };
    }
    payload[key] = n;
  }

  try {
    await saveSettings(payload);
  } catch (e) {
    return err(e, "Could not save settings.");
  }
  revalidatePath("/staff/settings");
  return { ok: true, message: "Settings saved." };
}

export async function saveRateItemAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const payload: Record<string, unknown> = {
    id: String(formData.get("id") ?? "") || null,
    code: String(formData.get("code") ?? ""),
    category: String(formData.get("category") ?? "material"),
    label: String(formData.get("label") ?? ""),
    description: String(formData.get("description") ?? ""),
    unit: String(formData.get("unit") ?? "sqft"),
    unit_price: Number(formData.get("unit_price") ?? 0),
    is_active: formData.get("is_active") === "on",
  };
  const sort = Number(formData.get("sort_order") ?? 0);
  if (!Number.isNaN(sort)) payload.sort_order = sort;

  try {
    await saveRateItem(payload);
  } catch (e) {
    return err(e, "Could not save that rate.");
  }
  revalidatePath("/staff/rates");
  return { ok: true, message: "Rate saved." };
}

export async function saveQuestionAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const min = String(formData.get("min_value") ?? "");
  const max = String(formData.get("max_value") ?? "");
  const step = String(formData.get("step_value") ?? "");

  const payload: Record<string, unknown> = {
    id: String(formData.get("id") ?? "") || null,
    key: String(formData.get("key") ?? ""),
    section: String(formData.get("section") ?? ""),
    label: String(formData.get("label") ?? ""),
    help_text: String(formData.get("help_text") ?? ""),
    input_type: String(formData.get("input_type") ?? "text"),
    unit: String(formData.get("unit") ?? ""),
    required: formData.get("required") === "on",
    affects_price: formData.get("affects_price") === "on",
    is_active: formData.get("is_active") === "on",
  };

  const optionsRaw = String(formData.get("options_json") ?? "").trim();
  if (optionsRaw) {
    try {
      const parsed = JSON.parse(optionsRaw);
      if (!Array.isArray(parsed)) {
        return { ok: false, message: "Options must be a JSON array." };
      }
      // rq_questions.options is an array of plain strings and every consumer
      // reads them as such. Rejecting objects here stops a save like
      // [{"value":"a","label":"A"}] from rendering blank dropdown entries later.
      if (!parsed.every((o) => typeof o === "string" && o.trim() !== "")) {
        return {
          ok: false,
          message:
            'Options must be plain strings, e.g. ["replacement","overlay"] — not objects with "value" or "label".',
        };
      }
      if (new Set(parsed).size !== parsed.length) {
        return { ok: false, message: "Options must not contain duplicates." };
      }
      payload.options = parsed;
    } catch {
      return { ok: false, message: "Options are not valid JSON." };
    }
  }
  if (min.trim()) payload.min_value = Number(min);
  if (max.trim()) payload.max_value = Number(max);
  if (step.trim()) payload.step_value = Number(step);

  try {
    await saveQuestion(payload);
  } catch (e) {
    return err(e, "Could not save that question.");
  }
  revalidatePath("/staff/questions");
  return { ok: true, message: "Question saved." };
}

export async function resetRateItemsAction(): Promise<void> {
  await resetRateItems();
  revalidatePath("/staff/rates");
}

export async function setLeadStatusAction(
  leadId: string,
  status: string,
): Promise<void> {
  await setLeadStatus(leadId, status);
  revalidatePath("/staff/leads");
}

export async function setQuoteStatusAction(
  quoteId: string,
  status: string,
): Promise<void> {
  await setQuoteStatus(quoteId, status);
  revalidatePath("/staff/quotes");
}

export async function regenerateQuoteAction(leadId: string): Promise<void> {
  await regenerateQuote(leadId);
  revalidatePath("/staff/quotes");
}
