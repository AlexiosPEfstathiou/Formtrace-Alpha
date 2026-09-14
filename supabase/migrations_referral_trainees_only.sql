-- =====================================================================
-- FormTrace — Item BV: referral tiers count referred TRAINEES only.
-- Run in the Supabase SQL editor (supersedes referral_stats from
-- migrations_badges.sql).
-- Decided 2026-09-14: tiers (Recruiter 3 / Ambassador 10 / Partner 25)
-- count referred people who completed a coaching goal AS A TRAINEE.
-- Referred coaches are tracked separately (qualified = approved as a
-- coach) and do not move the tier - recruiting coaches is the company's
-- strategy for now. Reward ladders differ by the REFERRER's role (BS).
-- =====================================================================
create or replace function public.referral_stats(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with r as (
    select p.id, p.role,
           exists (select 1 from public.engagements e where e.trainee_id = p.id and e.status = 'completed') as trainee_done
      from public.profiles p where p.referred_by = p_user
  ),
  c as (
    select count(*)::int                                          as signups,
           count(*) filter (where trainee_done)::int              as qualified,        -- tier basis: completed a goal as a trainee
           count(*) filter (where role = 'coach')::int            as coaches_referred  -- tracked, not tiered: approved as a coach
      from r
  )
  select jsonb_build_object(
    'signups',          c.signups,
    'qualified',        c.qualified,
    'coaches_referred', c.coaches_referred,
    'tier',      case when c.qualified >= 25 then 3 when c.qualified >= 10 then 2 when c.qualified >= 3 then 1 else 0 end,
    'title',     case when c.qualified >= 25 then 'Partner' when c.qualified >= 10 then 'Ambassador' when c.qualified >= 3 then 'Recruiter' else null end,
    'next_at',   case when c.qualified >= 25 then null when c.qualified >= 10 then 25 when c.qualified >= 3 then 10 else 3 end
  ) from c;
$$;
revoke execute on function public.referral_stats(uuid) from public;
grant  execute on function public.referral_stats(uuid) to authenticated;

select 'referral_stats updated' as check, 1;
