-- =====================================================================
-- FormTrace — Item AX: weekly nutrition goals (calories + protein).
-- Run in the Supabase SQL editor.
--
-- The coach's weekly task: set a DAILY calorie and protein target for each
-- trainee, per week (week_start = Monday). When the trainee logs macros they
-- see how close they came, as a percentage of that day's goal.
--
-- Carry-forward: if no row exists for a week, the most recent earlier goal
-- applies - a missed week never leaves a trainee goalless. The client shows
-- when a goal is carried rather than set for that week.
-- =====================================================================
create table if not exists public.macro_goals (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  week_start    date not null,
  kcal          integer check (kcal is null or kcal > 0),
  protein_g     integer check (protein_g is null or protein_g > 0),
  set_by        uuid not null references public.profiles(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (engagement_id, week_start)
);
create index if not exists macro_goals_eng_week_idx on public.macro_goals (engagement_id, week_start desc);

alter table public.macro_goals enable row level security;

drop policy if exists "parties read macro goals" on public.macro_goals;
create policy "parties read macro goals" on public.macro_goals
  for select to authenticated using (
    exists (select 1 from public.engagements e
             where e.id = macro_goals.engagement_id
               and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())));

drop policy if exists "coach writes macro goals" on public.macro_goals;
create policy "coach writes macro goals" on public.macro_goals
  for all to authenticated
  using (exists (select 1 from public.engagements e where e.id = macro_goals.engagement_id and e.coach_id = auth.uid()))
  with check (exists (select 1 from public.engagements e where e.id = macro_goals.engagement_id and e.coach_id = auth.uid())
              and set_by = auth.uid());

-- Effective goal for the calling TRAINEE on a given date: the latest goal at
-- or before that date's week, across all their active engagements (if two
-- coaches both set one, the most recently set wins). Usable from any screen -
-- the macro-log sheet opens from the homepage too, where no calendar state
-- is loaded.
create or replace function public.my_macro_goal(p_date date default current_date)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(g) || jsonb_build_object(
           'carried', g.week_start <> date_trunc('week', p_date::timestamp)::date,
           'goal_title', e.goal_title)
    from public.macro_goals g
    join public.engagements e on e.id = g.engagement_id
   where e.trainee_id = auth.uid()
     and e.status = 'active'
     and g.week_start <= date_trunc('week', p_date::timestamp)::date
   order by g.week_start desc, g.updated_at desc
   limit 1;
$$;
revoke execute on function public.my_macro_goal(date) from public;
grant execute on function public.my_macro_goal(date) to authenticated;

select 'macro_goals ready' as check, count(*) from public.macro_goals;
