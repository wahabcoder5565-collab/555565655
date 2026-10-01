-- Roofing Quote Generator :: stop claiming auth users that belong to other apps
--
-- rq_on_auth_user_created runs AFTER INSERT ON auth.users. On this shared
-- Supabase project that trigger also fires for signups from every other app in
-- the project, so it was creating a roofing contractor row for unrelated
-- accounts. A real example: admin@youpulse.app, which is not a roofing app,
-- ended up holding the is_primary contractor row. Because
-- rq_default_contractor_id() resolves the public wizard through is_primary,
-- the public site was pointed at that other app's blank contractor instead of
-- a real roofer.
--
-- The fix is to only claim users that actually signed up through this app.
-- signUpAction tags its signups with rq_app = 'roofing' in user_metadata, so
-- the trigger now requires that marker. rq_ensure_contractor() remains the lazy
-- fallback: an existing roofing user who predates the marker still gets a
-- contractor the first time they open /staff.
--
-- This is deliberately conservative: an unmarked user creates no row rather
-- than guessing. Nothing is deleted here, so no data is destroyed by applying
-- it; the orphaned row for another app's account is removed separately.

create or replace function public.rq_on_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Only claim signups that came from this app. On a shared project
  -- auth.users is inserted to by every other app as well.
  if coalesce(new.raw_user_meta_data ->> 'rq_app', '') <> 'roofing' then
    return new;
  end if;

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
    not exists (select 1 from public.rq_contractors)
  )
  on conflict (owner_id) do nothing;

  return new;
end;
$$;

revoke all on function public.rq_on_auth_user_created() from public;