-- =====================================================================
-- FormTrace — public coach profiles: badges, expertise, sub-ratings
-- Run in the Supabase SQL editor.
--
-- Coaching is a credence good: a trainee cannot judge quality even after
-- buying, so the profile has to carry signals that are costly to fake —
-- verified status, volume of work, and ratings broken into dimensions
-- rather than one star score that compresses to 5.
--
-- `stars` is KEPT as the overall score. Sub-ratings are added alongside and
-- are nullable, so existing ratings stay valid and new ones accumulate
-- detail without a backfill.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 1 — profile fields
-- ---------------------------------------------------------------------
alter table public.profiles
  add column if not exists expertise      text,
  add column if not exists pro_status     text not null default 'none',
  add column if not exists pro_since      timestamptz,
  add column if not exists certified_at   timestamptz;

-- 'none' -> 'professional' -> 'certified'. Certified is an evolution of
-- professional, never a parallel state, so the ladder is enforced here.
do $$
begin
  if not exists (select 1 from pg_constraint where conname='profiles_pro_status_chk') then
    alter table public.profiles add constraint profiles_pro_status_chk
      check (pro_status in ('none','professional','certified'));
  end if;
end $$;

-- Verified needs no column: it IS role='coach', which only an admin approval
-- can produce. Deriving it avoids a flag that could drift out of step.

-- pro_status is admin-granted only. Trainees discount self-declared badges,
-- and a coach able to set their own would make the badge worthless.
revoke update on public.profiles from authenticated;
grant  update (display_name, city, bio, avatar_initials, avatar_path,
               country_code, social_enabled, name_style, expertise,
               streak_count, milestone_ack)
  on public.profiles to authenticated;

-- ---------------------------------------------------------------------
-- PART 2 — sub-ratings
-- ---------------------------------------------------------------------
alter table public.ratings
  add column if not exists r_professionalism smallint,
  add column if not exists r_communication   smallint,
  add column if not exists r_motivation      smallint,
  add column if not exists r_price           smallint,
  add column if not exists r_instructions    smallint;

do $$
declare c text;
begin
  foreach c in array array['r_professionalism','r_communication','r_motivation','r_price','r_instructions']
  loop
    if not exists (select 1 from pg_constraint where conname='ratings_'||c||'_chk') then
      execute format('alter table public.ratings add constraint ratings_%s_chk check (%I is null or %I between 1 and 5)', c, c, c);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- PART 3 — one call for everything a public profile shows
--   SECURITY DEFINER so it can count engagements the viewer cannot read,
--   while returning only aggregates — never another trainee's identity.
-- ---------------------------------------------------------------------
create or replace function public.coach_public_profile(p_coach uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare out jsonb;
begin
  select jsonb_build_object(
    'id',            p.id,
    'display_name',  p.display_name,
    'name_style',    p.name_style,
    'city',          p.city,
    'country_code',  p.country_code,
    'bio',           p.bio,
    'expertise',     p.expertise,
    'avatar_path',   p.avatar_path,
    'avatar_initials',p.avatar_initials,
    'verified',      (p.role = 'coach'),
    'pro_status',    p.pro_status,
    'member_since',  p.created_at,
    'trainees_all_time', (select count(distinct e.trainee_id) from public.engagements e where e.coach_id = p.id),
    'goals_all_time',    (select count(*) from public.engagements e where e.coach_id = p.id),
    'goals_completed',   (select count(*) from public.engagements e where e.coach_id = p.id and e.status = 'completed'),
    'workouts_reviewed', (select count(*) from public.reviews r where r.coach_id = p.id),
    'rating_count',  (select count(*) from public.ratings r where r.ratee_id = p.id),
    'rating_avg',    (select round(avg(r.stars)::numeric,2) from public.ratings r where r.ratee_id = p.id),
    'sub',           (select jsonb_build_object(
                        'professionalism', round(avg(r.r_professionalism)::numeric,2),
                        'communication',   round(avg(r.r_communication)::numeric,2),
                        'motivation',      round(avg(r.r_motivation)::numeric,2),
                        'price',           round(avg(r.r_price)::numeric,2),
                        'instructions',    round(avg(r.r_instructions)::numeric,2))
                      from public.ratings r where r.ratee_id = p.id),
    'reviews',       (select coalesce(jsonb_agg(x order by x->>'created_at' desc), '[]'::jsonb)
                      from (
                        select jsonb_build_object(
                          'stars', r.stars,
                          'text', r.text,
                          'created_at', r.created_at,
                          'by', public.public_name(pr.display_name, coalesce(pr.name_style,'first'))
                        ) as x
                        from public.ratings r
                        join public.profiles pr on pr.id = r.rater_id
                        where r.ratee_id = p.id and r.text is not null and btrim(r.text) <> ''
                        order by r.created_at desc limit 20
                      ) s)
  ) into out
  from public.profiles p
  where p.id = p_coach and p.role = 'coach';
  return out;   -- null when the id isn't a coach
end;
$$;

revoke execute on function public.coach_public_profile(uuid) from public;
grant  execute on function public.coach_public_profile(uuid) to authenticated;

select proname from pg_proc where proname = 'coach_public_profile';
