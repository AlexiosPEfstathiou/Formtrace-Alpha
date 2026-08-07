-- =====================================================================
-- FormTrace — lock down media reads  (CRITICAL)
-- Run the whole file in the Supabase SQL editor, then paste the output
-- of the final SELECT back so the result can be verified.
--
-- PROBLEM
--   The videos bucket currently allows ANY authenticated user to read ANY
--   object. Set videos, coach references, feedback clips and — most
--   seriously — weekly check-in body photos are protected only by the
--   randomness of their filename. Any signed-in account can mint a signed
--   URL for any path, and a coach keeps that access forever, including
--   after an engagement ends.
--
-- WHY THIS NEEDS NO CLIENT CHANGES
--   Paths are {uid}/{uuid}.{ext} and carry no type information, so a
--   policy cannot tell a private check-in photo from a public pitch video
--   by path alone. But the app already records which objects are meant to
--   be public: listings.pitch_video_path, offers.pitch_video_path and
--   profiles.avatar_path. The policy below consults those tables, so
--   deliberately published media stays readable while private media does
--   not. No upload paths change and no existing object needs moving.
--
-- ACCESS GRANTED BY THE NEW POLICY
--   1. the owner of the object (first path segment = their user id)
--   2. the other party in an engagement with the owner (coach <-> trainee)
--   3. anyone, for a pitch video referenced by a listing or an offer
--      (the marketplace depends on this being browsable)
--   4. anyone, for an avatar referenced by a profile
--
-- NOT granted: unrelated users reading check-in photos, set videos,
--   references or feedback clips. That is the hole being closed.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1 — record what exists today, so it can be restored if needed
-- ---------------------------------------------------------------------
create table if not exists public.storage_policy_backup (
  id          bigserial primary key,
  policyname  text,
  cmd         text,
  qual        text,
  with_check  text,
  saved_at    timestamptz not null default now()
);

insert into public.storage_policy_backup (policyname, cmd, qual, with_check)
select policyname, cmd, qual::text, with_check::text
from pg_policies
where schemaname = 'storage' and tablename = 'objects';

alter table public.storage_policy_backup enable row level security;
-- RLS on with no policies: readable only via the SQL editor / service role.

-- ---------------------------------------------------------------------
-- STEP 2 — remove existing SELECT policies on storage.objects
--   Only SELECT policies are touched. INSERT/UPDATE/DELETE policies are
--   left exactly as they are, so uploading is unaffected.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select policyname
    from pg_policies
    where schemaname = 'storage'
      and tablename  = 'objects'
      and cmd in ('SELECT','ALL')
  loop
    execute format('drop policy if exists %I on storage.objects', r.policyname);
    raise notice 'dropped read policy: %', r.policyname;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- STEP 3 — scoped read access
-- ---------------------------------------------------------------------
drop policy if exists "ft read own or shared media" on storage.objects;
create policy "ft read own or shared media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'videos'
    and (
      -- 1. the owner
      split_part(name, '/', 1) = auth.uid()::text

      -- 2. the counterparty in an engagement with the owner
      or exists (
        select 1 from public.engagements e
        where (e.coach_id   = auth.uid() and e.trainee_id::text = split_part(name, '/', 1))
           or (e.trainee_id = auth.uid() and e.coach_id::text   = split_part(name, '/', 1))
      )

      -- 3. pitch videos published to the marketplace
      or exists (select 1 from public.listings l where l.pitch_video_path = name)
      or exists (select 1 from public.offers   o where o.pitch_video_path = name)

      -- 4. profile photos
      or exists (select 1 from public.profiles p where p.avatar_path = name)
    )
  );

-- ---------------------------------------------------------------------
-- STEP 4 — verify. Expect exactly one SELECT policy, named
--          "ft read own or shared media", plus your existing write
--          policies untouched.
-- ---------------------------------------------------------------------
select policyname, cmd
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
order by cmd, policyname;

-- ---------------------------------------------------------------------
-- ROLLBACK, if something breaks:
--   select * from public.storage_policy_backup order by saved_at desc;
--   -- then recreate the previous policy from the saved qual text and
--   -- drop "ft read own or shared media".
-- ---------------------------------------------------------------------
