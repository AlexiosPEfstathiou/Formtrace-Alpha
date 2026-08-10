-- =====================================================================
-- FormTrace — age on public profiles
-- Run in the Supabase SQL editor. Requires migrations_coach_profiles.sql.
--
-- Age is now shown publicly. Date of birth STAYS in profile_private with
-- owner-only RLS: this function is SECURITY DEFINER, so it can read the date
-- and return only the derived integer. A viewer therefore learns the age but
-- can never recover the birth date, which is the part worth protecting.
--
-- The consent notice has been updated to say age is publicly visible and
-- CONSENT_VERSION bumped in the client, so every existing user is re-prompted
-- BEFORE their age becomes visible to anyone.
-- =====================================================================

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
    -- whole years only; the date itself never leaves the database
    'age',           (select case
                        when pv.date_of_birth is null then null
                        else extract(year from age(current_date, pv.date_of_birth))::int
                      end
                      from public.profile_private pv where pv.user_id = p.id),
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
  return out;
end;
$$;

revoke execute on function public.coach_public_profile(uuid) from public;
grant  execute on function public.coach_public_profile(uuid) to authenticated;

-- how many people will need to re-consent under the new notice
select count(*) as awaiting_new_consent
from public.profile_private
where consent_version is distinct from '2026-08-v2';
