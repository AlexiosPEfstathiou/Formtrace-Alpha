-- =====================================================================
-- FormTrace — item L: languages on profiles
-- Run in the Supabase SQL editor.
--
-- Fixed list (ISO 639-1 codes), not free text — the actual reason this was
-- requested is filtering/matching ("a trainee who only speaks Spanish
-- needs to know before messaging"), and free text can't be filtered
-- reliably without normalising it server-side. Same pattern already used
-- for country_code: store the code, let Intl.DisplayNames render the
-- localised name client-side, so no name list needs shipping or maintaining.
--
-- No marketplace filter UI exists yet to consume this (checked — "Find a
-- coach" is a reverse marketplace where coaches respond to posted goals,
-- not a browsable directory), so this is informational display only for
-- now: shown on the coach's public profile. Filtering is a separate,
-- later piece of work if a browse screen is ever built.
-- =====================================================================

alter table public.profiles
  add column if not exists languages text[];

grant update (languages) on public.profiles to authenticated;

-- one call for everything a public profile shows (item A) — adding
-- languages to the same payload rather than a second round trip
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
    'languages',     p.languages,
    'avatar_path',   p.avatar_path,
    'avatar_initials',p.avatar_initials,
    'verified',      (p.role = 'coach'),
    'pro_status',    p.pro_status,
    'member_since',  p.created_at,
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

select proname from pg_proc where proname = 'coach_public_profile';
