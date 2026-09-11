-- =====================================================================
-- FormTrace — DIAGNOSTIC (read-only): why a streak dropped after a vacation.
-- Run in the Supabase SQL editor. Changes nothing. Replace the email.
--
-- Reads out, week by week around the vacation, what close_week recorded:
-- assigned/completed counts, neutral flag + reason, and any pause overlap.
-- The week the streak walk STOPS at is the first one below (reading top-down
-- from the most recent) that is NOT neutral and has completed < assigned.
-- =====================================================================
with me as (
  select id from public.profiles
   where id = (select id from auth.users where email = 'REPLACE_WITH_YOUR_EMAIL')
)
select
  c.week_start,
  to_char(c.week_start,'Dy DD Mon') as week_of,
  c.assigned_count  as assigned,
  c.completed_count as completed,
  c.neutral,
  c.neutral_reason,
  exists (
    select 1 from public.engagement_pauses p
     where p.engagement_id = c.engagement_id
       and p.starts_on <= c.week_start + 6
       and coalesce(p.ends_on, c.week_start + 6) >= c.week_start
  ) as pause_overlaps_week,
  case
    when c.neutral then 'skip (neutral)'
    when c.completed_count >= c.assigned_count then 'EXTENDS streak'
    else 'BREAKS streak here'
  end as streak_effect
from public.week_closures c
join public.engagements e on e.id = c.engagement_id
where e.trainee_id = (select id from me)
order by c.week_start desc
limit 30;

-- also: the raw pause rows, so we can see the real vacation window
select 'PAUSES' as section, p.starts_on, p.ends_on,
       date_trunc('week', p.starts_on::timestamp)::date as first_paused_week,
       date_trunc('week', coalesce(p.ends_on, p.starts_on)::timestamp)::date as last_paused_week
  from public.engagement_pauses p
  join public.engagements e on e.id = p.engagement_id
 where e.trainee_id = (select id from auth.users where email = 'REPLACE_WITH_YOUR_EMAIL')
 order by p.starts_on desc;
