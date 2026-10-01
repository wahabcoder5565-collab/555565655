-- Roofing Quote Generator :: new sign ups become contractors
--
-- A contractor does not get a private copy of the system rate card and
-- questionnaire. rq_effective_rate_items and rq_effective_questions already
-- fall back to the shared rows, and the dashboard only writes an override when
-- the contractor actually changes something. So signing up is a single row, and
-- the shared defaults keep improving for everyone automatically.

create or replace function public.rq_on_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.rq_contractors (
    owner_id, company_name, contact_email, is_primary
  )
  values (
    new.id,
    left(coalesce(new.raw_user_meta_data ->> 'company_name', ''), 160),
    lower(left(coalesce(new.email, ''), 200)),
    -- The first contractor to exist is the one the public wizard points at.
    not exists (select 1 from public.rq_contractors)
  )
  on conflict (owner_id) do nothing;

  return new;
end;
$$;

drop trigger if exists rq_on_auth_user_created on auth.users;
create trigger rq_on_auth_user_created
  after insert on auth.users
  for each row execute function public.rq_on_auth_user_created();

revoke all on function public.rq_on_auth_user_created() from public;

-- There is deliberately no backfill here. An earlier version created a
-- contractor for every pre-existing auth.users row, which on a shared project
-- claimed accounts belonging to other applications. rq_ensure_contractor()
-- covers anyone who signs in without a contractor row, and a user with no
-- contractor simply sees the "no contractor set up yet" state on the public
-- wizard until the first genuine sign up.
