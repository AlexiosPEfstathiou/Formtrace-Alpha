-- =====================================================================
-- FormTrace — Item BN part 1: coach referral links, counts, tier badge.
-- Run in the Supabase SQL editor.
--
-- Every profile gets a short referral code. A new trainee who opens the app
-- through ?ref=CODE has their profile stamped ONCE (referred_by) at first
-- sign-in. Two counts are kept, deliberately - the "what counts" decision
-- is thereby not blocked:
--   signups   = profiles referred by this coach
--   qualified = of those, trainees who went on to accept an offer (have an
--               engagement) - not gameable by making accounts
-- Tiers key on QUALIFIED. The money parts (commission discounts, a share on
-- a referred trainee who later coaches) are item BI's territory and not here.
-- =====================================================================
alter table public.profiles
  add column if not exists referral_code text unique
    default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  add column if not exists referred_by uuid references public.profiles(id) on delete set null,
  add column if not exists referred_at timestamptz;

update public.profiles set referral_code = upper(substr(md5(gen_random_uuid()::text), 1, 8))
 where referral_code is null;

-- ---------- claim: called once, by the new account, right after first sign-in ----------
create or replace function public.claim_referral(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_me record;
  v_ref record;
begin
  if uid is null then raise exception 'not signed in'; end if;
  select id, referred_by, created_at into v_me from public.profiles where id = uid;
  if not found then raise exception 'no profile'; end if;
  if v_me.referred_by is not null then return null; end if;                  -- already stamped: never overwrite
  if v_me.created_at < now() - interval '7 days' then return null; end if;   -- only new accounts can be referred
  select id, display_name, role into v_ref from public.profiles
   where referral_code = upper(trim(p_code)) and role = 'coach';            -- coaches' links only (per the request)
  if not found then return null; end if;
  if v_ref.id = uid then return null; end if;                               -- no self-referral
  update public.profiles set referred_by = v_ref.id, referred_at = now() where id = uid;
  return v_ref.display_name;
end;
$$;
revoke execute on function public.claim_referral(text) from public;
grant  execute on function public.claim_referral(text) to authenticated;

-- ---------- stats: counts + derived tier, readable by anyone signed in ----------
create or replace function public.referral_stats(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with r as (
    select p.id,
           exists (select 1 from public.engagements e where e.trainee_id = p.id) as qualified
      from public.profiles p where p.referred_by = p_user
  ),
  c as (
    select count(*)::int as signups, count(*) filter (where qualified)::int as qualified from r
  )
  select jsonb_build_object(
    'signups',   c.signups,
    'qualified', c.qualified,
    'tier',      case when c.qualified >= 25 then 3 when c.qualified >= 10 then 2 when c.qualified >= 3 then 1 else 0 end,
    'title',     case when c.qualified >= 25 then 'Partner' when c.qualified >= 10 then 'Ambassador' when c.qualified >= 3 then 'Referrer' else null end,
    'next_at',   case when c.qualified >= 25 then null when c.qualified >= 10 then 25 when c.qualified >= 3 then 10 else 3 end
  ) from c;
$$;
revoke execute on function public.referral_stats(uuid) from public;
grant  execute on function public.referral_stats(uuid) to authenticated;

select 'profiles with referral_code' as check, count(*) from public.profiles where referral_code is not null;
