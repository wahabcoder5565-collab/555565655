import type { Metadata } from "next";
import Link from "next/link";
import { listLeads } from "@/lib/rq/staff";
import { StatusSelect } from "@/components/status-select";

export const metadata: Metadata = { title: "Leads" };

export default async function LeadsPage() {
  const { rows: leads, total } = await listLeads({ limit: 100 });

  return (
    <div>
      <h1 className="text-2xl font-bold tracking-tight">Leads</h1>
      <p className="mt-1 text-sm text-slate-600">
        Every roof enquiry that started the wizard.
      </p>

      {leads.length === 0 ? (
        <p className="mt-8 rounded-xl border border-dashed border-slate-300 p-8 text-center text-sm text-slate-500">
          No leads yet. Share your quote link to start collecting them.
        </p>
      ) : (
        <>
          <p className="mt-4 text-xs text-slate-500">
            Showing {leads.length} of {total}
            {total > leads.length ? " — narrow the list to see older ones." : ""}
          </p>
          <div className="mt-2 overflow-x-auto rounded-xl border border-slate-200 bg-white">
            <table className="w-full text-sm">
              <thead className="border-b border-slate-200 bg-slate-50 text-left text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-3 font-medium">Contact</th>
                  <th className="px-4 py-3 font-medium">Project</th>
                  <th className="px-4 py-3 font-medium">Progress</th>
                  <th className="px-4 py-3 font-medium">Quotes</th>
                  <th className="px-4 py-3 font-medium">Status</th>
                  <th className="px-4 py-3 font-medium">Created</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {leads.map((lead) => (
                  <tr key={lead.id}>
                    <td className="px-4 py-3">
                      <p className="font-medium">{lead.contact_name || "—"}</p>
                      <p className="text-xs text-slate-500">{lead.contact_email}</p>
                      {lead.contact_phone && (
                        <p className="text-xs text-slate-500">{lead.contact_phone}</p>
                      )}
                    </td>
                    <td className="px-4 py-3 text-slate-600">
                      {lead.property_address || "—"}
                      {(lead.property_city || lead.property_state) && (
                        <p className="text-xs text-slate-500">
                          {[lead.property_city, lead.property_state]
                            .filter(Boolean)
                            .join(", ")}{" "}
                          {lead.property_zip}
                        </p>
                      )}
                    </td>
                    <td className="px-4 py-3 tabular-nums text-slate-600">
                      {lead.submitted_at
                        ? "Submitted"
                        : `${Math.round((lead.completion ?? 0) * 100)}%`}
                    </td>
                    <td className="px-4 py-3 tabular-nums text-slate-600">
                      {lead.quote_count > 0 && lead.latest_quote_id ? (
                        <Link
                          href={`/staff/quotes/${lead.latest_quote_id}`}
                          className="font-medium underline"
                        >
                          {lead.latest_quote_number ?? "View"}
                        </Link>
                      ) : (
                        <span className="text-slate-400">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <StatusSelect id={lead.id} kind="lead" value={lead.status} />
                    </td>
                    <td className="px-4 py-3 text-xs text-slate-500">
                      {new Date(lead.created_at).toLocaleDateString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </>
      )}

      <p className="mt-6 text-xs text-slate-400">
        Looking for the paperwork?{" "}
        <Link href="/staff/quotes" className="underline">
          Open the quote list
        </Link>
        .
      </p>
    </div>
  );
}