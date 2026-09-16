-- =====================================================================
-- FormTrace — Item CH: exit survey when a goal ends early.
-- Run in the Supabase SQL editor (after migrations_goal_feedback.sql).
-- Reuses goal_feedback: kind = 'completion' (CC) | 'exit' (CH).
-- =====================================================================
alter table public.goal_feedback add column if not exists kind text not null default 'completion'
  check (kind in ('completion','exit'));
alter table public.goal_feedback drop constraint if exists goal_feedback_engagement_id_role_key;
alter table public.goal_feedback drop constraint if exists goal_feedback_engagement_role_kind_key;
alter table public.goal_feedback add constraint goal_feedback_engagement_role_kind_key unique (engagement_id, role, kind);

select 'goal_feedback kinds' as check, count(*) from information_schema.columns
 where table_schema='public' and table_name='goal_feedback' and column_name='kind';
