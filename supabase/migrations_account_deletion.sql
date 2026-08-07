-- =====================================================================
-- FormTrace — account deletion by anonymisation  (Option B)
-- Run the whole file in the Supabase SQL editor.
--
-- WHY NOT A HARD DELETE
--   profiles.id references auth.users on delete cascade, and EVERY table
--   referencing profiles(id) is also on delete cascade. Removing a profile
--   would chain through engagements -> assigned_workouts -> submissions ->
--   set_labels -> reviews. A departing coach would take their trainees'
--   entire workout history with them, and the labelled grading data would
--   be destroyed. So the profiles row is deliberately KEPT and scrubbed.
--
-- WHAT ERASURE MEANS HERE
--   Deleted outright : check-in photos, all videos, macro logs, body
--                      measurements, quarterly measurements, ratings text
--   Scrubbed         : display name, bio, city, country, avatar, social flag
--   Auth             : email replaced with a non-routable address so the
--                      account cannot be signed into or recovered
--   Kept anonymised  : engagements, workouts, submissions, set labels,
--                      reviews — the counterparty's history and the
--                      training corpus, now attached to "Deleted user"
-- =====================================================================

alter table public.profiles
  add column if not exists deleted_at timestamptz;

-- ---------------------------------------------------------------------
-- PREVIEW — run this before deleting anything. Returns counts only.
-- ---------------------------------------------------------------------
create or replace function public.my_data_summary()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  out jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select jsonb_build_object(
    'macro_logs',        (select count(*) from public.logs         where trainee_id = uid),
    'checkin_photos',    (select count(*) from public.checkins     where trainee_id = uid),
    'body_measurements', (select count(*) from public.measurements where trainee_id = uid),
    'stored_files',      (select count(*) from storage.objects
                            where bucket_id = 'videos'
                              and split_part(name,'/',1) = uid::text),
    'goals_as_trainee',  (select count(*) from public.engagements  where trainee_id = uid),
    'goals_as_coach',    (select count(*) from public.engagements  where coach_id   = uid),
    'submissions',       (select count(*) from public.submissions  where trainee_id = uid),
    'reviews_written',   (select count(*) from public.reviews      where coach_id   = uid),
    'exercises',         (select count(*) from public.exercises    where coach_id   = uid),
    'workouts',          (select count(*) from public.workouts     where coach_id   = uid),
    'listings',          (select count(*) from public.listings     where trainee_id = uid),
    'offers',            (select count(*) from public.offers
                            where coach_id = uid or trainee_id = uid),
    'ratings',           (select count(*) from public.ratings      where rater_id = uid)
  ) into out;
  return out;
end;
$$;

-- ---------------------------------------------------------------------
-- DELETE — irreversible. Scrubs identity, removes personal data,
--          keeps shared records against an anonymous profile.
-- ---------------------------------------------------------------------
create or replace function public.delete_my_account()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  files_removed int := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  -- 1. purely personal data: gone
  delete from public.logs         where trainee_id = uid;
  delete from public.checkins     where trainee_id = uid;
  delete from public.measurements where trainee_id = uid;

  -- 2. free-text the user wrote about other people
  update public.ratings set text = null where rater_id = uid;
  delete from public.coach_applications where user_id = uid;

  -- 3. media. The client removes the actual objects first; this clears any
  --    rows it could not reach so nothing stays referenced.
  delete from storage.objects
   where bucket_id = 'videos'
     and split_part(name,'/',1) = uid::text;
  get diagnostics files_removed = row_count;

  -- 4. detach media paths that pointed at the deleted files
  update public.listings set pitch_video_path = null where trainee_id = uid;
  update public.offers   set pitch_video_path = null where coach_id   = uid;
  update public.day_notes set video_path = null where coach_id = uid;
  update public.exercises set ref_video_path = null where coach_id = uid;

  -- 5. close active relationships so nobody is left waiting on a ghost
  update public.engagements
     set status = 'ended', completed_at = coalesce(completed_at, now())
   where (trainee_id = uid or coach_id = uid) and status = 'active';
  update public.listings set status = 'closed' where trainee_id = uid and status = 'open';
  update public.offers   set status = 'expired' where coach_id = uid and status = 'pending';

  -- 6. scrub the identity but KEEP the row, so shared history survives
  update public.profiles
     set display_name    = 'Deleted user',
         bio             = null,
         city            = null,
         country_code    = null,
         avatar_initials = null,
         avatar_path     = null,
         social_enabled  = false,
         name_style      = 'first',
         streak_count    = 0,
         deleted_at      = now()
   where id = uid;

  -- 7. make the login unusable and remove the email. The address becomes
  --    non-routable, so the account cannot be signed into or recovered.
  update auth.users
     set email              = 'deleted-' || replace(uid::text,'-','') || '@deleted.invalid',
         phone              = null,
         raw_user_meta_data = '{}'::jsonb
   where id = uid;

  return jsonb_build_object('ok', true, 'storage_rows_cleared', files_removed);
end;
$$;

revoke execute on function public.my_data_summary()   from public;
revoke execute on function public.delete_my_account() from public;
grant  execute on function public.my_data_summary()   to authenticated;
grant  execute on function public.delete_my_account() to authenticated;

-- verify
select proname from pg_proc
where proname in ('my_data_summary','delete_my_account')
order by proname;
