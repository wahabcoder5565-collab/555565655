-- Roofing Quote Generator :: undo the sign up backfill
--
-- Migration 0009 backfilled a contractor row for every row already in
-- auth.users. On this shared project that meant creating a roofing contractor
-- for 57 users who belong to entirely different applications, and arbitrarily
-- promoting one of them to be the primary contractor that the public quote
-- wizard points at.
--
-- A contractor row should only ever come into existence through the
-- rq_on_auth_user_created trigger, which fires for genuine new sign ups. The
-- backfill is removed from 0009 as well; this migration only cleans up what it
-- already wrote.

-- Only placeholder rows are removed. Anything with a quote request attached has
-- actually been used and is left untouched.
delete from public.rq_contractors c
where not exists (
  select 1 from public.rq_leads l where l.contractor_id = c.id
);
