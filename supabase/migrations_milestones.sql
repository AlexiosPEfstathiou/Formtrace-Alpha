-- =====================================================================
-- FormTrace — streak milestone acknowledgement
-- Run in the Supabase SQL editor.
--
-- Milestones (7, 14, 30, 60, 90, 180, 270, 365 days) put a button on the
-- trainee's homepage that persists until they tap it. That needs somewhere
-- to remember what has been acknowledged.
--
-- Stored on profiles rather than localStorage so the celebration follows
-- the trainee across devices and survives clearing site data.
--
-- Semantics: milestone_ack holds the DAY COUNT of the highest milestone
-- already celebrated. If a streak breaks and is rebuilt, the client lowers
-- this value so the milestone can be earned again.
-- =====================================================================

alter table public.profiles
  add column if not exists milestone_ack integer not null default 0;

select count(*) filter (where milestone_ack > 0) as already_celebrated,
       count(*) as total
from public.profiles;
