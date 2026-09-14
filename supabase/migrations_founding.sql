-- =====================================================================
-- FormTrace — Item BQ: "Founding coach" badge, assigned manually by the
-- project owner (admin). Run in the Supabase SQL editor.
-- Founding coaches are chosen by hand (decided 2026-09-14), not by rule.
-- The badge shows on the public coach profile next to Verified /
-- Professional / Certified / referral tier. Item BR (zero commission for
-- founders) reads the same column once BI exists.
-- =====================================================================
alter table public.profiles add column if not exists founding_at timestamptz;

create or replace function public.admin_set_founding(p_coach uuid, p_on boolean)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin boolean;
  v_val timestamptz;
begin
  select is_admin into v_admin from public.profiles where id = auth.uid();
  if not coalesce(v_admin,false) then raise exception 'admin only'; end if;
  if not exists (select 1 from public.profiles where id = p_coach and role = 'coach') then
    raise exception 'not a coach';
  end if;
  update public.profiles
     set founding_at = case when p_on then coalesce(founding_at, now()) else null end
   where id = p_coach
   returning founding_at into v_val;
  return v_val;
end;
$$;
revoke execute on function public.admin_set_founding(uuid, boolean) from public;
grant  execute on function public.admin_set_founding(uuid, boolean) to authenticated;

select 'founding coaches' as check, count(*) from public.profiles where founding_at is not null;
