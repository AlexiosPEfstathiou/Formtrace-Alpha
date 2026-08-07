-- =====================================================================
-- FormTrace — client error reporting
-- Run in the Supabase SQL editor.
--
-- WHY
--   A failure on a trainee's phone is currently invisible unless they
--   mention it. Most of the bugs found so far were silent: a caught
--   exception logged to a console nobody reads. This gives those a
--   destination.
--
-- PRIVACY
--   Deliberately narrow: message, stack, active screen, user agent. No
--   request bodies, no form values, no photo or video paths. Users can
--   INSERT their own rows and cannot read anyone's, including their own —
--   only an admin can read. That keeps it a diagnostic channel rather
--   than a second copy of user data.
-- =====================================================================

create table if not exists public.client_errors (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete set null,
  occurred_at timestamptz not null default now(),
  kind        text not null default 'error',
  message     text,
  stack       text,
  screen      text,
  ua          text,
  app_version text
);

alter table public.client_errors enable row level security;

-- write-only for users: you may report, you may not browse
drop policy if exists "report own errors" on public.client_errors;
create policy "report own errors"
  on public.client_errors for insert to authenticated
  with check (user_id = auth.uid());

-- is_admin() is SECURITY DEFINER (added in migrations_profile_privacy.sql)
-- so this does not recurse through profiles' own policies.
drop policy if exists "admins read errors" on public.client_errors;
create policy "admins read errors"
  on public.client_errors for select to authenticated
  using (public.is_admin());

drop policy if exists "admins clear errors" on public.client_errors;
create policy "admins clear errors"
  on public.client_errors for delete to authenticated
  using (public.is_admin());

create index if not exists client_errors_recent_idx
  on public.client_errors (occurred_at desc);

-- Housekeeping: this table only has diagnostic value while it is fresh.
-- Run occasionally, or wire to a scheduled job:
--   delete from public.client_errors where occurred_at < now() - interval '30 days';

select policyname, cmd from pg_policies
where schemaname='public' and tablename='client_errors' order by cmd;
