-- ============================================================
-- FormTrace Coach — Alpha schema (Supabase / Postgres)
-- Run this whole file in the Supabase SQL Editor (one paste).
-- Order matters: tables first, then RLS policies, then storage.
-- ============================================================

-- ---------- PROFILES ----------
-- One row per auth user. Created automatically on sign-up via trigger below.
-- role: 'trainee' (default) or 'coach' (set only when an application is approved).
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  role         text not null default 'trainee' check (role in ('trainee','coach')),
  is_admin     boolean not null default false,
  display_name text,
  bio          text,
  city         text,
  avatar_initials text,
  streak_count integer not null default 0,
  created_at   timestamptz not null default now()
);

-- ---------- COACH APPLICATIONS ----------
-- A trainee applies; admin approves/rejects. Approval flips profiles.role to 'coach'.
create table if not exists public.coach_applications (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  status        text not null default 'pending' check (status in ('pending','approved','rejected')),
  full_name     text,
  qualifications text,
  experience    text,
  specialties   text,
  price_band    text,
  note          text,
  reviewed_by   uuid references public.profiles(id),
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now()
);

-- ---------- EXERCISES (coach library) ----------
create table if not exists public.exercises (
  id            uuid primary key default gen_random_uuid(),
  coach_id      uuid not null references public.profiles(id) on delete cascade,
  name          text not null,
  cues          text,
  ref_video_path text,          -- Supabase Storage path to reference video
  landmarks     jsonb,          -- captured reference rep (skeleton frames)
  created_at    timestamptz not null default now()
);

-- ---------- WORKOUTS (coach library: ordered set of exercises + volume) ----------
create table if not exists public.workouts (
  id          uuid primary key default gen_random_uuid(),
  coach_id    uuid not null references public.profiles(id) on delete cascade,
  name        text not null,
  items       jsonb not null default '[]',  -- [{exercise_id, sets, reps}, ...]
  created_at  timestamptz not null default now()
);

-- ---------- LISTINGS (trainee posts a goal to the marketplace) ----------
create table if not exists public.listings (
  id           uuid primary key default gen_random_uuid(),
  trainee_id   uuid not null references public.profiles(id) on delete cascade,
  title        text not null,
  focus        text,
  details      text,
  pitch_video_path text,        -- trainee's video describing their goal
  status       text not null default 'open' check (status in ('open','matched','closed')),
  created_at   timestamptz not null default now()
);

-- ---------- OFFERS (coach -> trainee, always carries a video pitch) ----------
create table if not exists public.offers (
  id           uuid primary key default gen_random_uuid(),
  listing_id   uuid references public.listings(id) on delete set null,
  coach_id     uuid not null references public.profiles(id) on delete cascade,
  trainee_id   uuid not null references public.profiles(id) on delete cascade,
  kind         text not null default 'offer' check (kind in ('offer','renewal')),
  title        text not null,
  focus        text,
  length_text  text,
  start_text   text,
  sessions_text text,
  price_text   text,
  pitch_video_path text not null,   -- required video pitch (Storage path)
  voucher_cents integer not null default 0,
  status       text not null default 'pending' check (status in ('pending','accepted','rejected','expired')),
  expires_at   timestamptz,
  created_at   timestamptz not null default now()
);

-- ---------- ENGAGEMENTS (an active coach<->trainee relationship) ----------
create table if not exists public.engagements (
  id           uuid primary key default gen_random_uuid(),
  offer_id     uuid references public.offers(id) on delete set null,
  coach_id     uuid not null references public.profiles(id) on delete cascade,
  trainee_id   uuid not null references public.profiles(id) on delete cascade,
  goal_title   text,
  status       text not null default 'active' check (status in ('active','completed','ended')),
  outcome      text check (outcome in ('on_time','late',null)),
  started_at   timestamptz not null default now(),
  completed_at timestamptz
);

-- ---------- ASSIGNED WORKOUTS (coach assigns a workout within an engagement) ----------
create table if not exists public.assigned_workouts (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  workout_id    uuid references public.workouts(id) on delete set null,
  snapshot      jsonb not null,   -- frozen copy of workout+exercises at assign time
  due_date      date,
  status        text not null default 'assigned' check (status in ('assigned','submitted','reviewed')),
  created_at    timestamptz not null default now()
);

-- ---------- SUBMISSIONS (trainee performs an assigned workout) ----------
create table if not exists public.submissions (
  id            uuid primary key default gen_random_uuid(),
  assigned_id   uuid not null references public.assigned_workouts(id) on delete cascade,
  trainee_id    uuid not null references public.profiles(id) on delete cascade,
  report        jsonb not null,   -- the .ftr.json payload (landmark frames + grades)
  created_at    timestamptz not null default now()
);

-- ---------- REVIEWS (per submission: coach feedback, may carry video) ----------
create table if not exists public.reviews (
  id            uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions(id) on delete cascade,
  coach_id      uuid not null references public.profiles(id) on delete cascade,
  overall       text,
  per_set       jsonb,            -- [{set, label, comment, video_path}, ...]
  created_at    timestamptz not null default now()
);

-- ---------- MUTUAL RATINGS (both sides rate at goal completion) ----------
create table if not exists public.ratings (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  rater_id      uuid not null references public.profiles(id) on delete cascade,
  ratee_id      uuid not null references public.profiles(id) on delete cascade,
  stars         integer not null check (stars between 1 and 5),
  text          text,
  created_at    timestamptz not null default now(),
  unique (engagement_id, rater_id)
);

-- ---------- LOGS (trainee daily weight/macros) ----------
create table if not exists public.logs (
  id          uuid primary key default gen_random_uuid(),
  trainee_id  uuid not null references public.profiles(id) on delete cascade,
  log_date    date not null,
  weight_kg   numeric,
  kcal        integer,
  protein_g   integer,
  carbs_g     integer,
  fat_g       integer,
  created_at  timestamptz not null default now(),
  unique (trainee_id, log_date)
);

-- ============================================================
-- TRIGGER: auto-create a profile row when a user signs up
-- ============================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_initials)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)),
    upper(left(coalesce(new.raw_user_meta_data->>'display_name', new.email), 2))
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- FUNCTION: approve a coach application (admin only)
-- Flips the applicant's role to 'coach' and stamps the review.
-- ============================================================
create or replace function public.approve_coach_application(app_id uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  v_uid uuid;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then
    raise exception 'Only admins can approve applications';
  end if;

  select user_id into v_uid from public.coach_applications where id = app_id;
  if v_uid is null then
    raise exception 'Application not found';
  end if;

  update public.coach_applications
     set status='approved', reviewed_by=auth.uid(), reviewed_at=now()
   where id=app_id;

  update public.profiles set role='coach' where id=v_uid;
end;
$$;

-- ============================================================
-- ROW LEVEL SECURITY
-- Enable on every table, then add policies.
-- Principle: users see their own data + the counterparty's data
-- within a shared engagement/offer. Coaches are publicly viewable.
-- ============================================================
alter table public.profiles          enable row level security;
alter table public.coach_applications enable row level security;
alter table public.exercises         enable row level security;
alter table public.workouts          enable row level security;
alter table public.listings          enable row level security;
alter table public.offers            enable row level security;
alter table public.engagements       enable row level security;
alter table public.assigned_workouts enable row level security;
alter table public.submissions       enable row level security;
alter table public.reviews           enable row level security;
alter table public.ratings           enable row level security;
alter table public.logs              enable row level security;

-- ---------- PROFILES ----------
-- Anyone signed in can read profiles (needed to browse coaches / see names).
create policy "profiles readable by authenticated"
  on public.profiles for select to authenticated using (true);
-- You can update only your own profile (role is protected: see note in README).
create policy "update own profile"
  on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- ---------- COACH APPLICATIONS ----------
create policy "insert own application"
  on public.coach_applications for insert to authenticated
  with check (user_id = auth.uid());
create policy "read own application or admin"
  on public.coach_applications for select to authenticated
  using (user_id = auth.uid() or exists
    (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));
create policy "admin updates applications"
  on public.coach_applications for update to authenticated
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- ---------- EXERCISES & WORKOUTS (coach owns; trainee sees via snapshot) ----------
create policy "coach manages own exercises"
  on public.exercises for all to authenticated
  using (coach_id = auth.uid()) with check (coach_id = auth.uid());
create policy "coach manages own workouts"
  on public.workouts for all to authenticated
  using (coach_id = auth.uid()) with check (coach_id = auth.uid());

-- ---------- LISTINGS (trainee owns; coaches can read open listings) ----------
create policy "trainee manages own listings"
  on public.listings for all to authenticated
  using (trainee_id = auth.uid()) with check (trainee_id = auth.uid());
create policy "coaches read open listings"
  on public.listings for select to authenticated
  using (status = 'open' and exists
    (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'coach'));

-- ---------- OFFERS (visible to the two parties only) ----------
create policy "coach creates offers"
  on public.offers for insert to authenticated
  with check (coach_id = auth.uid());
create policy "parties read offers"
  on public.offers for select to authenticated
  using (coach_id = auth.uid() or trainee_id = auth.uid());
create policy "trainee responds to offers"
  on public.offers for update to authenticated
  using (trainee_id = auth.uid() or coach_id = auth.uid());

-- ---------- ENGAGEMENTS (the two parties) ----------
create policy "parties manage engagements"
  on public.engagements for all to authenticated
  using (coach_id = auth.uid() or trainee_id = auth.uid())
  with check (coach_id = auth.uid() or trainee_id = auth.uid());

-- ---------- ASSIGNED / SUBMISSIONS / REVIEWS (scoped via engagement) ----------
create policy "assigned visible to parties"
  on public.assigned_workouts for all to authenticated
  using (exists (select 1 from public.engagements e
    where e.id = engagement_id and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())))
  with check (exists (select 1 from public.engagements e
    where e.id = engagement_id and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())));

create policy "trainee writes own submissions"
  on public.submissions for insert to authenticated
  with check (trainee_id = auth.uid());
create policy "parties read submissions"
  on public.submissions for select to authenticated
  using (trainee_id = auth.uid() or exists
    (select 1 from public.assigned_workouts a join public.engagements e on e.id=a.engagement_id
     where a.id = assigned_id and e.coach_id = auth.uid()));

create policy "coach writes reviews"
  on public.reviews for insert to authenticated
  with check (coach_id = auth.uid());
create policy "parties read reviews"
  on public.reviews for select to authenticated
  using (coach_id = auth.uid() or exists
    (select 1 from public.submissions s where s.id = submission_id and s.trainee_id = auth.uid()));

-- ---------- RATINGS (public read for reputation; write your own) ----------
create policy "ratings readable"
  on public.ratings for select to authenticated using (true);
create policy "write own ratings"
  on public.ratings for insert to authenticated
  with check (rater_id = auth.uid());

-- ---------- LOGS (trainee owns; their coaches may read) ----------
create policy "trainee manages own logs"
  on public.logs for all to authenticated
  using (trainee_id = auth.uid()) with check (trainee_id = auth.uid());
create policy "coach reads trainee logs"
  on public.logs for select to authenticated
  using (exists (select 1 from public.engagements e
    where e.trainee_id = logs.trainee_id and e.coach_id = auth.uid() and e.status='active'));

-- ============================================================
-- STORAGE: one bucket for all video (pitches, reviews, references)
-- Private bucket; access via signed URLs generated by the client.
-- Path convention: {auth.uid()}/{uuid}.webm  -> owner is first folder.
-- ============================================================
insert into storage.buckets (id, name, public)
values ('videos', 'videos', false)
on conflict (id) do nothing;

-- Upload: only into your own folder (first path segment = your uid).
create policy "upload own videos"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text);

-- Read: any authenticated user may request a signed URL for a video in this
-- bucket. (Alpha simplification — tighten to engagement scoping post-alpha.)
create policy "read videos authenticated"
  on storage.objects for select to authenticated
  using (bucket_id = 'videos');

-- Delete: only your own uploads.
create policy "delete own videos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- DONE. After running: create your admin user by signing up in the
-- app, then run (once) in this editor, replacing the email:
--   update public.profiles set is_admin = true
--   where id = (select id from auth.users where email = 'you@example.com');
-- ============================================================
