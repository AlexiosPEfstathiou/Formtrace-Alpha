-- =====================================================================
-- FormTrace — Item BC: trim offsets per video (start/end), offset-based.
-- Run in the Supabase SQL editor. Extends video_orientation - the per-path
-- metadata table already used for rotation (one row fixes a clip on every
-- surface it appears). Same reasoning as rotation: applied at playback,
-- instant, lossless, reversible, no re-encoding. A true recut would need a
-- mux library, which the Artifactory policy prevents installing.
-- =====================================================================
alter table public.video_orientation
  add column if not exists trim_in  numeric check (trim_in  is null or trim_in  >= 0),
  add column if not exists trim_out numeric check (trim_out is null or trim_out > 0);

comment on column public.video_orientation.trim_in  is 'seconds: playback starts here (Item BC)';
comment on column public.video_orientation.trim_out is 'seconds: playback stops here (Item BC)';

select 'video_orientation trim columns' as check, count(*) from information_schema.columns
 where table_schema='public' and table_name='video_orientation' and column_name in ('trim_in','trim_out');
