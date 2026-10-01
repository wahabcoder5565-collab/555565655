-- Roofing Quote Generator :: carry the rest of the signup metadata into the contractor
--
-- rq_on_auth_user_created() only copied company_name and contact_email off
-- new.raw_user_meta_data. The staff signup form also asks for phone, city and
-- state, and those values were being accepted by the form, passed through
-- Supabase, and then silently discarded when the trigger built the contractor
-- row. The person then had to retype them in /staff/settings.
--
-- All three are columns rq_staff_save_settings already accepts, so this only
-- aligns the signup path with the settings path. The lengths mirror the column
-- limits so a long value is trimmed rather than rejected by the insert.

create or replace function public.rq_on_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.rq_contractors (
    owner_id, company_name, contact_email, phone, city, state, is_primary
  )
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'company_name', ''), 160),
    lower(left(coalesce(new.email, ''), 200)),
    left(coalesce(new.raw_user_meta_data ->> 'phone', ''), 40),
    left(coalesce(new.raw_user_meta_data ->> 'city', ''), 100),
    left(coalesce(new.raw_user_meta_data ->> 'state', ''), 40),
    -- The first contractor to exist is the one the public wizard points at.
    not exists (select 1 from public.rq_contractors)
  )
  on conflict (owner_id) do nothing;

  return new;
end;
$$;

revoke all on function public.rq_on_auth_user_created() from public;