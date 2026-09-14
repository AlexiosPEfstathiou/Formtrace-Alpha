-- =====================================================================
-- FormTrace — Item BX: coach "Top 1%" badge from trainees' combined streaks.
-- Run in the Supabase SQL editor.
-- Score = sum of current week streaks over a coach's ACTIVE trainees (sum,
-- not average - rewards coaching many people well). Ranked among coaches
-- with at least one active trainee; the top ceil(1%) hold the badge,
-- MINIMUM ONE holder (decided 2026-09-14). A one-week grace after losing
-- the rank keeps the badge from flickering at the boundary.
-- =====================================================================
create table if not exists public.coach_streak_score (
  coach_id     uuid primary key references public.profiles(id) on delete cascade,
  score        integer not null default 0,
  trainees     integer not null default 0,
  rank         integer,
  of_coaches   integer,
  top1         boolean not null default false,
  top1_last_at timestamptz,
  computed_at  timestamptz not null default now()
);
alter table public.coach_streak_score enable row level security;
drop policy if exists "streak scores are public" on public.coach_streak_score;
create policy "streak scores are public" on public.coach_streak_score
  for select to authenticated using (true);

-- Recompute for everyone. Cheap; skips if computed within the last 6 hours
-- unless p_force. Called from the app when a coach opens home.
create or replace function public.refresh_coach_streak_scores(p_force boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_last timestamptz;
  v_n int;
  v_slots int;
begin
  select max(computed_at) into v_last from public.coach_streak_score;
  if not p_force and v_last is not null and v_last > now() - interval '6 hours' then
    return jsonb_build_object('skipped', true, 'computed_at', v_last);
  end if;

  create temp table _s on commit drop as
    select e.coach_id,
           coalesce(sum(coalesce(p.week_streak_count,0)),0)::int as score,
           count(distinct e.trainee_id)::int as trainees
      from public.engagements e
      join public.profiles p on p.id = e.trainee_id
     where e.status = 'active'
     group by e.coach_id;

  select count(*) into v_n from _s;
  v_slots := greatest(1, ceil(v_n * 0.01)::int);   -- top 1%, minimum one holder

  insert into public.coach_streak_score (coach_id, score, trainees, rank, of_coaches, top1, top1_last_at, computed_at)
  select s.coach_id, s.score, s.trainees,
         rank() over (order by s.score desc, s.trainees desc, s.coach_id),
         v_n,
         (rank() over (order by s.score desc, s.trainees desc, s.coach_id)) <= v_slots and s.score > 0,
         case when (rank() over (order by s.score desc, s.trainees desc, s.coach_id)) <= v_slots and s.score > 0 then now() end,
         now()
    from _s s
  on conflict (coach_id) do update
    set score = excluded.score, trainees = excluded.trainees, rank = excluded.rank, of_coaches = excluded.of_coaches,
        top1 = excluded.top1,
        top1_last_at = coalesce(excluded.top1_last_at, public.coach_streak_score.top1_last_at),
        computed_at = now();

  -- coaches with no active trainees drop out of the ranking
  update public.coach_streak_score c
     set score = 0, trainees = 0, rank = null, of_coaches = v_n, top1 = false, computed_at = now()
   where not exists (select 1 from _s where _s.coach_id = c.coach_id);

  return jsonb_build_object('coaches', v_n, 'slots', v_slots, 'computed_at', now());
end;
$$;
revoke execute on function public.refresh_coach_streak_scores(boolean) from public;
grant  execute on function public.refresh_coach_streak_scores(boolean) to authenticated;

select public.refresh_coach_streak_scores(true) as first_run;
