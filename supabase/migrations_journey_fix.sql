-- =====================================================================
-- FormTrace — DS: the journey recap failed with
-- "function pg_catalog.extract(unknown, integer) does not exist". In Postgres, date - date
-- is already an integer number of days; extract(epoch from …) needs an interval. Only the
-- 'weeks' line changes; the rest of journey_summary is unchanged.
-- =====================================================================
create or replace function public.journey_summary(p_engagement uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  eng record;
  out jsonb;
  d_from date; d_to date;
  w_start numeric; w_end numeric;
begin
  select e.id, e.trainee_id, e.coach_id, e.started_at, e.completed_at, e.status
    into eng
  from public.engagements e where e.id = p_engagement;
  if eng.id is null then raise exception 'goal not found'; end if;
  if eng.trainee_id <> auth.uid() and eng.coach_id <> auth.uid() then
    raise exception 'not authorised';
  end if;

  d_from := eng.started_at::date;
  d_to   := coalesce(eng.completed_at::date, current_date);

  select l.weight_kg into w_start from public.logs l
    where l.trainee_id = eng.trainee_id and l.log_date >= d_from and l.weight_kg is not null
    order by l.log_date asc limit 1;
  select l.weight_kg into w_end from public.logs l
    where l.trainee_id = eng.trainee_id and l.log_date <= d_to and l.weight_kg is not null
    order by l.log_date desc limit 1;

  select jsonb_build_object(
    'engagement_id', eng.id,
    'trainee_id', eng.trainee_id,
    'started_at', eng.started_at,
    'completed_at', eng.completed_at,
    'weeks', greatest(1, round((d_to - d_from) / 7.0)::int),   -- DS: date - date is already a number of days
    'peak_streak', public.peak_streak_in_range(eng.trainee_id, d_from, d_to),
    'weight_start', w_start,
    'weight_end', w_end,
    'checkin_count', (select count(*) from public.checkins c
                        where c.trainee_id = eng.trainee_id
                          and c.checkin_date >= d_from and c.checkin_date <= d_to)
  ) into out;
  return out;
end;
$$;

-- proof of the arithmetic: 1 Aug → 29 Oct 2026 is 89 days = 13 weeks
select greatest(1, round((date '2026-10-29' - date '2026-08-01') / 7.0)::int) as weeks_check;
