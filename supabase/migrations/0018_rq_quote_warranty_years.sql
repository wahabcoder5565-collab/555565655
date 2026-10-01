-- Roofing Quote Generator :: expose the workmanship warranty on customer quotes
--
-- The warranty term is a contractual commitment the customer needs to see, and
-- the contractor already sets it in /staff/settings. rq_public_quote projects
-- the contractor row for the quote footer but left warranty_years out, so the
-- quote page could not print the term it is being held to.
--
-- This is a widening of the public projection, so it is deliberately limited to
-- the single non-commercial field that was missing. Margin, rates and cost data
-- are untouched.

create or replace function public.rq_public_quote(p_token text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_quote public.rq_quotes;
  v_c public.rq_contractors;
  v_lead public.rq_leads;
begin
  select * into v_quote from public.rq_quotes where public_token = p_token;
  if not found then
    raise exception 'Quote not found' using errcode = 'no_data_found';
  end if;

  select l.* into v_lead from public.rq_leads l where l.id = v_quote.lead_id;
  select * into v_c from public.rq_contractors where id = v_quote.contractor_id;

  if v_quote.status = 'sent' then
    update public.rq_quotes
    set status = 'viewed', viewed_at = now()
    where id = v_quote.id;

    insert into public.rq_quote_events (quote_id, lead_id, actor_role, action, detail)
    values (v_quote.id, v_lead.id, 'customer', 'quote_viewed', 'Customer opened the quote');

    v_quote.status := 'viewed';
    v_quote.viewed_at := now();
  end if;

  return jsonb_build_object(
    'quote', to_jsonb(v_quote) - 'answers' - 'pricing' - 'notes',
    'answers', v_quote.answers,
    'pricing', v_quote.pricing,
    'items', coalesce((
      select jsonb_agg(to_jsonb(i) order by i.sort_order)
      from public.rq_quote_items i
      where i.quote_id = v_quote.id
    ), '[]'::jsonb),
    'customer', jsonb_build_object(
      'contact_name', v_lead.contact_name,
      'contact_email', v_lead.contact_email,
      'contact_phone', v_lead.contact_phone,
      'property_address', v_lead.property_address,
      'property_city', v_lead.property_city,
      'property_state', v_lead.property_state,
      'property_zip', v_lead.property_zip
    ),
    'contractor', jsonb_build_object(
      'company_name', v_c.company_name,
      'phone', v_c.phone,
      'website', v_c.website,
      'license_no', v_c.license_no,
      'address_line', v_c.address_line,
      'city', v_c.city,
      'state', v_c.state,
      'zip_code', v_c.zip_code,
      'logo_url', v_c.logo_url,
      'brand_color', v_c.brand_color,
      'terms', v_c.terms,
      'warranty_years', v_c.warranty_years
    )
  );
end;
$$;

-- Signature is unchanged, so existing grants from 0015 still apply. The revoke
-- is repeated defensively in case this is ever replayed onto a database that
-- has not had 0015 applied.
revoke all on function public.rq_public_quote(text) from public;
grant execute on function public.rq_public_quote(text) to anon, authenticated;