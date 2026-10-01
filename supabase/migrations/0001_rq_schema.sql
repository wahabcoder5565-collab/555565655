-- Roofing Quote Generator :: schema
-- Money math lives in Postgres. The LLM only ever writes prose on top of a
-- quote that these tables already priced.

create table if not exists public.rq_contractors (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users (id) on delete cascade,
  company_name text not null default '',
  contact_email text not null default '',
  phone text not null default '',
  license_no text not null default '',
  website text not null default '',
  address_line text not null default '',
  city text not null default '',
  state text not null default '',
  zip_code text not null default '',
  currency text not null default 'USD',
  logo_url text not null default '',
  brand_color text not null default '#0f766e',
  terms text not null default '',
  -- pricing knobs
  waste_factor_pct numeric(5, 2) not null default 10,
  overhead_pct numeric(5, 2) not null default 12,
  profit_pct numeric(5, 2) not null default 18,
  contingency_pct numeric(5, 2) not null default 0,
  tax_pct numeric(5, 2) not null default 0,
  min_charge numeric(12, 2) not null default 1500,
  deposit_pct numeric(5, 2) not null default 30,
  valid_days integer not null default 30,
  warranty_years integer not null default 10,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.rq_contractors is
  'One roofing contractor per signed-in user. Holds the pricing knobs that drive every quote.';

-- Rate card: the pricing menu the contractor sets. contractor_id null = system default.
create table if not exists public.rq_rate_items (
  id uuid primary key default gen_random_uuid(),
  contractor_id uuid references public.rq_contractors (id) on delete cascade,
  code text not null,
  category text not null default 'material'
    check (category in (
      'material', 'underlayment', 'accessory', 'teardown',
      'disposal', 'labor', 'permit', 'protection'
    )),
  label text not null,
  description text not null default '',
  unit text not null default 'sqft'
    check (unit in ('sqft', 'square', 'linear_ft', 'each', 'sheet', 'hour')),
  unit_cost numeric(12, 2) not null default 0,
  unit_price numeric(12, 2) not null default 0,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rq_rate_items_contractor_idx
  on public.rq_rate_items (contractor_id, category, sort_order);

create unique index if not exists rq_rate_items_code_scope_idx
  on public.rq_rate_items (coalesce(contractor_id, '00000000-0000-0000-0000-000000000000'::uuid), code);

-- Questionnaire definition. contractor_id null = system template shared by everyone.
create table if not exists public.rq_questions (
  id uuid primary key default gen_random_uuid(),
  contractor_id uuid references public.rq_contractors (id) on delete cascade,
  key text not null,
  section text not null default 'roof',
  label text not null,
  help_text text not null default '',
  input_type text not null default 'number'
    check (input_type in ('number', 'select', 'boolean', 'text', 'multi_select')),
  unit text not null default '',
  options jsonb not null default '[]'::jsonb,
  required boolean not null default false,
  affects_price boolean not null default true,
  min_value numeric(12, 2),
  max_value numeric(12, 2),
  step_value numeric(12, 2),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rq_questions_contractor_idx
  on public.rq_questions (contractor_id, section, sort_order);

create unique index if not exists rq_questions_key_scope_idx
  on public.rq_questions (coalesce(contractor_id, '00000000-0000-0000-0000-000000000000'::uuid), key);

-- A customer working through the wizard. public_token is the only credential the
-- anonymous visitor ever holds.
create table if not exists public.rq_leads (
  id uuid primary key default gen_random_uuid(),
  public_token text not null unique,
  contractor_id uuid not null references public.rq_contractors (id) on delete cascade,
  contact_name text not null default '',
  contact_email text not null default '',
  contact_phone text not null default '',
  property_address text not null default '',
  property_city text not null default '',
  property_state text not null default '',
  property_zip text not null default '',
  project_type text not null default 'replacement',
  answers jsonb not null default '{}'::jsonb,
  current_step integer not null default 0,
  completion smallint not null default 0,
  status text not null default 'draft'
    check (status in ('draft', 'submitted', 'quoted', 'contacted', 'won', 'lost')),
  utm_source text not null default '',
  utm_campaign text not null default '',
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rq_leads_contractor_idx
  on public.rq_leads (contractor_id, status, created_at desc);

create index if not exists rq_leads_token_idx on public.rq_leads (public_token);

create sequence if not exists public.rq_quote_number_seq;

create table if not exists public.rq_quotes (
  id uuid primary key default gen_random_uuid(),
  public_token text not null unique,
  quote_number text not null unique,
  lead_id uuid not null references public.rq_leads (id) on delete cascade,
  contractor_id uuid not null references public.rq_contractors (id) on delete cascade,
  status text not null default 'draft'
    check (status in ('draft', 'sent', 'viewed', 'accepted', 'declined', 'expired')),
  project_type text not null default 'replacement',
  roof_area_sqft numeric(12, 2) not null default 0,
  inputs jsonb not null default '{}'::jsonb,
  answers jsonb not null default '{}'::jsonb,
  pricing jsonb not null default '{}'::jsonb,
  subtotal numeric(12, 2) not null default 0,
  contingency_total numeric(12, 2) not null default 0,
  overhead_total numeric(12, 2) not null default 0,
  profit_total numeric(12, 2) not null default 0,
  tax_total numeric(12, 2) not null default 0,
  min_charge_adjustment numeric(12, 2) not null default 0,
  total numeric(12, 2) not null default 0,
  deposit_amount numeric(12, 2) not null default 0,
  price_per_sqft numeric(12, 2) not null default 0,
  warnings jsonb not null default '[]'::jsonb,
  ai_scope_of_work text not null default '',
  ai_summary text not null default '',
  ai_recommendations jsonb not null default '[]'::jsonb,
  ai_risk_notes jsonb not null default '[]'::jsonb,
  ai_engine text not null default 'rules',
  ai_model text,
  ai_status text not null default 'pending'
    check (ai_status in ('pending', 'ready', 'failed')),
  ai_error text,
  ai_generated_at timestamptz,
  valid_until date,
  notes text not null default '',
  sent_at timestamptz,
  viewed_at timestamptz,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists rq_quotes_contractor_idx
  on public.rq_quotes (contractor_id, status, created_at desc);

create index if not exists rq_quotes_lead_idx on public.rq_quotes (lead_id);

create index if not exists rq_quotes_token_idx on public.rq_quotes (public_token);

create table if not exists public.rq_quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.rq_quotes (id) on delete cascade,
  category text not null default 'material',
  code text not null default '',
  label text not null,
  description text not null default '',
  quantity numeric(12, 2) not null default 0,
  unit text not null default 'sqft',
  unit_price numeric(12, 2) not null default 0,
  line_total numeric(12, 2) not null default 0,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists rq_quote_items_quote_idx
  on public.rq_quote_items (quote_id, sort_order);

create table if not exists public.rq_quote_events (
  id bigint generated always as identity primary key,
  quote_id uuid references public.rq_quotes (id) on delete cascade,
  lead_id uuid references public.rq_leads (id) on delete cascade,
  actor_id uuid,
  actor_role text not null default 'system',
  action text not null,
  detail text not null default '',
  created_at timestamptz not null default now()
);

create index if not exists rq_quote_events_quote_idx
  on public.rq_quote_events (quote_id, created_at desc);

create or replace function public.rq_set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists rq_contractors_touch on public.rq_contractors;
create trigger rq_contractors_touch
  before update on public.rq_contractors
  for each row execute function public.rq_set_updated_at();

drop trigger if exists rq_rate_items_touch on public.rq_rate_items;
create trigger rq_rate_items_touch
  before update on public.rq_rate_items
  for each row execute function public.rq_set_updated_at();

drop trigger if exists rq_questions_touch on public.rq_questions;
create trigger rq_questions_touch
  before update on public.rq_questions
  for each row execute function public.rq_set_updated_at();

drop trigger if exists rq_leads_touch on public.rq_leads;
create trigger rq_leads_touch
  before update on public.rq_leads
  for each row execute function public.rq_set_updated_at();

drop trigger if exists rq_quotes_touch on public.rq_quotes;
create trigger rq_quotes_touch
  before update on public.rq_quotes
  for each row execute function public.rq_set_updated_at();