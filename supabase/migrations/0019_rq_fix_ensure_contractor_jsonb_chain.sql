-- Roofing Quote Generator :: fix operator error creating the first contractor
--
-- rq_ensure_contractor() read the signup company name with:
--
--   coalesce(auth.jwt() ->> 'user_metadata' ->> 'company_name', '')
--
-- That is two ->> operators in a row. The first ->> extracts a JSON value as
-- text, so the second one is applied to a text value and Postgres rejects it:
--
--   ERROR: operator does not exist: text ->> unknown
--
-- The first hop has to use ->, which preserves the jsonb type, so the second
-- ->> can extract from it. This is the same shape already used correctly in
-- rq_is_admin (0002), which reads auth.jwt() -> 'app_metadata' ->> 'role'.
--
-- Why it went unnoticed: the faulty expression only executes on the insert
-- branch, when the caller does not already own a contractor. Every test so far
-- reused a pre-existing row, so the line never ran. The failure only surfaced
-- for the very first real signup on a clean database, where
-- rq_staff_bootstrap() could not create the primary contractor and the staff
-- dashboard errored on every page load.

create or replace function public.rq_ensure_contractor()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select c.id into v_id
  from public.rq_contractors c
  where c.owner_id = auth.uid()
  limit 1;

  if v_id is null then
    insert into public.rq_contractors (
      owner_id, company_name, contact_email, is_primary
    )
    values (
      auth.uid(),
      -- -> keeps this jsonb so the following ->> can read a nested key.
      left(coalesce(auth.jwt() -> 'user_metadata' ->> 'company_name', ''), 160),
      lower(coalesce(auth.jwt() ->> 'email', '')),
      not exists (select 1 from public.rq_contractors)
    )
    on conflict (owner_id) do nothing
    returning id into v_id;

    if v_id is null then
      select c.id into v_id
      from public.rq_contractors c
      where c.owner_id = auth.uid()
      limit 1;
    end if;
  end if;

  return v_id;
end;
$$;

-- Signature unchanged, so the existing authenticated grant from 0015 still
-- applies. Repeated defensively for a database that has not had 0015 applied.
revoke all on function public.rq_ensure_contractor() from public;
grant execute on function public.rq_ensure_contractor() to authenticated;