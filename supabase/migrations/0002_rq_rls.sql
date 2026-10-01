-- Roofing Quote Generator :: identity helpers, RLS, grants
--
-- Trust model:
--   * Anonymous visitors never touch a table directly. They hold a `public_token`
--     and go through SECURITY DEFINER RPCs that are the only place a token is
--     accepted as a credential.
--   * Signed-in staff see exactly their own contractor's rows.
--   * System defaults (contractor_id is null) are readable by any signed-in user
--     but writable only by a platform admin.

create or replace function public.rq_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

create or replace function public.rq_my_contractor_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select c.id
  from public.rq_contractors c
  where c.owner_id = auth.uid()
  limit 1;
$$;

create or replace function public.rq_owns_row(p_contractor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.rq_is_admin()
    or (
      p_contractor_id is not null
      and p_contractor_id = public.rq_my_contractor_id()
    );
$$;

revoke all on function public.rq_is_admin() from public;
revoke all on function public.rq_my_contractor_id() from public;
revoke all on function public.rq_owns_row(uuid) from public;

-- ---------------------------------------------------------------------------
-- rq_contractors
-- ---------------------------------------------------------------------------
alter table public.rq_contractors enable row level security;
alter table public.rq_contractors force row level security;

drop policy if exists rq_contractors_select on public.rq_contractors;
create policy rq_contractors_select on public.rq_contractors
  for select to authenticated
  using (owner_id = auth.uid() or rq_is_admin());

drop policy if exists rq_contractors_update on public.rq_contractors;
create policy rq_contractors_update on public.rq_contractors
  for update to authenticated
  using (owner_id = auth.uid() or rq_is_admin())
  with check (owner_id = auth.uid() or rq_is_admin());

-- ---------------------------------------------------------------------------
-- rq_rate_items / rq_questions  (own rows + shared system defaults)
-- ---------------------------------------------------------------------------
alter table public.rq_rate_items enable row level security;
alter table public.rq_rate_items force row level security;

drop policy if exists rq_rate_items_select on public.rq_rate_items;
create policy rq_rate_items_select on public.rq_rate_items
  for select to authenticated
  using (contractor_id is null or rq_owns_row(contractor_id));

drop policy if exists rq_rate_items_write on public.rq_rate_items;
create policy rq_rate_items_write on public.rq_rate_items
  for all to authenticated
  using (rq_owns_row(contractor_id))
  with check (rq_owns_row(contractor_id));

alter table public.rq_questions enable row level security;
alter table public.rq_questions force row level security;

drop policy if exists rq_questions_select on public.rq_questions;
create policy rq_questions_select on public.rq_questions
  for select to authenticated
  using (contractor_id is null or rq_owns_row(contractor_id));

drop policy if exists rq_questions_write on public.rq_questions;
create policy rq_questions_write on public.rq_questions
  for all to authenticated
  using (rq_owns_row(contractor_id))
  with check (rq_owns_row(contractor_id));

-- ---------------------------------------------------------------------------
-- rq_leads / rq_quotes / rq_quote_items / rq_quote_events
-- Staff-only. The public flow reaches these exclusively through token-scoped
-- SECURITY DEFINER RPCs, which bypass RLS by design and re-check the token.
-- ---------------------------------------------------------------------------
alter table public.rq_leads enable row level security;
alter table public.rq_leads force row level security;

drop policy if exists rq_leads_select on public.rq_leads;
create policy rq_leads_select on public.rq_leads
  for select to authenticated
  using (rq_owns_row(contractor_id));

drop policy if exists rq_leads_write on public.rq_leads;
create policy rq_leads_write on public.rq_leads
  for all to authenticated
  using (rq_owns_row(contractor_id))
  with check (rq_owns_row(contractor_id));

alter table public.rq_quotes enable row level security;
alter table public.rq_quotes force row level security;

drop policy if exists rq_quotes_select on public.rq_quotes;
create policy rq_quotes_select on public.rq_quotes
  for select to authenticated
  using (rq_owns_row(contractor_id));

drop policy if exists rq_quotes_write on public.rq_quotes;
create policy rq_quotes_write on public.rq_quotes
  for all to authenticated
  using (rq_owns_row(contractor_id))
  with check (rq_owns_row(contractor_id));

alter table public.rq_quote_items enable row level security;
alter table public.rq_quote_items force row level security;

drop policy if exists rq_quote_items_select on public.rq_quote_items;
create policy rq_quote_items_select on public.rq_quote_items
  for select to authenticated
  using (
    exists (
      select 1 from public.rq_quotes q
      where q.id = quote_id and rq_owns_row(q.contractor_id)
    )
  );

drop policy if exists rq_quote_items_write on public.rq_quote_items;
create policy rq_quote_items_write on public.rq_quote_items
  for all to authenticated
  using (
    exists (
      select 1 from public.rq_quotes q
      where q.id = quote_id and rq_owns_row(q.contractor_id)
    )
  )
  with check (
    exists (
      select 1 from public.rq_quotes q
      where q.id = quote_id and rq_owns_row(q.contractor_id)
    )
  );

alter table public.rq_quote_events enable row level security;
alter table public.rq_quote_events force row level security;

drop policy if exists rq_quote_events_select on public.rq_quote_events;
create policy rq_quote_events_select on public.rq_quote_events
  for select to authenticated
  using (
    exists (
      select 1 from public.rq_quotes q
      where q.id = quote_id and rq_owns_row(q.contractor_id)
    )
  );

drop policy if exists rq_quote_events_write on public.rq_quote_events;
create policy rq_quote_events_write on public.rq_quote_events
  for insert to authenticated
  with check (
    exists (
      select 1 from public.rq_quotes q
      where q.id = quote_id and rq_owns_row(q.contractor_id)
    )
  );

-- ---------------------------------------------------------------------------
-- Grants. No table is readable by anon; the wizard runs entirely on RPCs.
-- ---------------------------------------------------------------------------
revoke all on table
  public.rq_contractors, public.rq_rate_items, public.rq_questions,
  public.rq_leads, public.rq_quotes, public.rq_quote_items,
  public.rq_quote_events
from anon;

grant select, insert, update, delete on table
  public.rq_contractors, public.rq_rate_items, public.rq_questions,
  public.rq_leads, public.rq_quotes, public.rq_quote_items
to authenticated;

grant select, insert on table public.rq_quote_events to authenticated;

grant usage, select on sequence public.rq_quote_number_seq to authenticated;