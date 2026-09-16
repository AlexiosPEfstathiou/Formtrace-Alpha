-- =====================================================================
-- FormTrace — Item CC: goal-completion questionnaire (both roles).
-- Run in the Supabase SQL editor.
-- One row per (engagement, role). answers is jsonb keyed by question id:
--   { "q1": {"v": 4, "note": "…"}, ... }   v = scale/choice value
-- A dismissed row has answers null and dismissed_at set - shown once, then
-- gone. Questions themselves live in the app (one JS constant), so they
-- can change without a schema change; the answers carry the question ids.
-- =====================================================================
create table if not exists public.goal_feedback (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  user_id       uuid not null references public.profiles(id) on delete cascade,
  role          text not null check (role in ('trainee','coach')),
  version       integer not null default 1,
  answers       jsonb,
  dismissed_at  timestamptz,
  submitted_at  timestamptz not null default now(),
  unique (engagement_id, role)
);
alter table public.goal_feedback enable row level security;

drop policy if exists "own feedback" on public.goal_feedback;
create policy "own feedback" on public.goal_feedback
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "admin reads feedback" on public.goal_feedback;
create policy "admin reads feedback" on public.goal_feedback
  for select to authenticated using (exists (select 1 from public.profiles where id = auth.uid() and is_admin));

select 'goal_feedback' as check, count(*) from public.goal_feedback;
