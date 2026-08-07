-- =====================================================================
-- FormTrace — per-video rotation override
-- Run in the Supabase SQL editor.
--
-- WHY A SEPARATE TABLE
--   Video paths live in six different columns (set_labels.trainee_video_path,
--   exercises.ref_video_path, listings/offers.pitch_video_path,
--   day_notes.video_path, submission reports). Keying the override on the
--   storage path means one row fixes a clip on every surface it appears,
--   instead of adding a rotation column to each table.
--
-- WHY NOT RE-ENCODE
--   Rotation is applied as a CSS transform on playback: instant, lossless,
--   reversible, and no server-side video processing.
--
-- WHO MAY FIX A CLIP
--   The person who filmed it (their id is the first path segment), and the
--   other party in an engagement with them — a coach reviewing a sideways
--   video shouldn't have to ask the trainee to correct it.
-- =====================================================================

create table if not exists public.video_orientation (
  path       text primary key,
  rotation   integer not null default 0 check (rotation in (0,90,180,270)),
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.video_orientation enable row level security;

-- anyone signed in may READ an override; the storage policy still governs
-- whether they can actually fetch the object itself
drop policy if exists "read video orientation" on public.video_orientation;
create policy "read video orientation"
  on public.video_orientation for select to authenticated using (true);

-- writing is limited to the owner of the clip or their counterparty
drop policy if exists "set video orientation" on public.video_orientation;
create policy "set video orientation"
  on public.video_orientation for all to authenticated
  using (
    split_part(path,'/',1) = auth.uid()::text
    or exists (
      select 1 from public.engagements e
      where (e.coach_id = auth.uid() and e.trainee_id::text = split_part(path,'/',1))
         or (e.trainee_id = auth.uid() and e.coach_id::text = split_part(path,'/',1))
    )
  )
  with check (
    split_part(path,'/',1) = auth.uid()::text
    or exists (
      select 1 from public.engagements e
      where (e.coach_id = auth.uid() and e.trainee_id::text = split_part(path,'/',1))
         or (e.trainee_id = auth.uid() and e.coach_id::text = split_part(path,'/',1))
    )
  );

select policyname, cmd from pg_policies
where schemaname='public' and tablename='video_orientation' order by cmd;
