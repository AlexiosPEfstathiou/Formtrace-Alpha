-- =====================================================================
-- FormTrace — "The Journey": data for the goal-completion recap
-- Run in the Supabase SQL editor. Requires migrations_streak_redefine.sql
-- (uses public._day_state, defined there).
--
-- WHY A NEW FUNCTION RATHER THAN REUSING compute_streak
--   compute_streak always answers "the streak ending today" — it anchors on
--   the most recent non-missed day and walks outward. A finished goal needs
--   a different question: the LONGEST run anywhere inside a fixed past
--   window. Same day-state rule (done/rest/missed, 7 consecutive rest days
--   breaks a run), different walk — forward once through the window,
--   tracking the best run seen rather than anchoring on "now".
-- =====================================================================

create or replace function public.peak_streak_in_range(p_trainee uuid, p_from date, p_to date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cur date := p_from;
  run integer := 0;
  rest integer := 0;
  best integer := 0;
  guard integer := 0;
  st text;
begin
  if p_from is null or p_to is null or p_to < p_from then return 0; end if;
  while cur <= p_to and guard < 1000 loop
    st := public._day_state(p_trainee, cur);
    if st = 'missed' then
      run := 0; rest := 0;
    elsif st = 'rest' then
      rest := rest + 1;
      if rest >= 7 then run := 0; rest := 0;   -- a full week off still breaks a run
      else run := run + 1; end if;
    else
      run := run + 1; rest := 0;
    end if;
    if run > best then best := run; end if;
    cur := cur + 1; guard := guard + 1;
  end loop;
  return best;
end;
$$;

revoke execute on function public.peak_streak_in_range(uuid,date,date) from public;
grant  execute on function public.peak_streak_in_range(uuid,date,date) to authenticated;

-- ---------------------------------------------------------------------
-- One call for the whole recap screen: duration, peak streak, and the
-- weight at goal start vs. its end, computed server-side so the client
-- doesn't have to fetch the entire logs history just to find two numbers.
-- ---------------------------------------------------------------------
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
    'weeks', greatest(1, round(extract(epoch from (d_to - d_from)) / (7*86400))::int),
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

revoke execute on function public.journey_summary(uuid) from public;
grant  execute on function public.journey_summary(uuid) to authenticated;

select proname from pg_proc where proname in ('peak_streak_in_range','journey_summary') order by proname;
