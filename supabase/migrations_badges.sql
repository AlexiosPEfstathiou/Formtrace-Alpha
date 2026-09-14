-- =====================================================================
-- FormTrace — Item BH/BQ: the badge system, made concrete.
-- Run in the Supabase SQL editor (after migrations_founding.sql).
--
-- Verified      = role coach; verified_at is the approval date (backfilled
--                 from the application's reviewed_at). Hover shows the date.
-- Professional  = admin-assigned, with an employer: "Works at <place>".
-- Certified     = the COACH attaches a certification (title, date, file);
--                 an ADMIN approves it; pro_status becomes 'certified' and
--                 the summary (title, date) shows on their profile.
-- Founding      = admin-assigned, no explanation stored; hover says the
--                 coach has been part of the app's development.
-- Referral tier = Recruiter / Ambassador / Partner (renamed from Referrer);
--                 hover shows the referral number.
-- =====================================================================
alter table public.profiles
  add column if not exists verified_at  timestamptz,
  add column if not exists pro_employer text;

update public.profiles p
   set verified_at = coalesce(p.verified_at,
        (select max(a.reviewed_at) from public.coach_applications a where a.user_id = p.id and a.status = 'approved'),
        p.created_at)
 where p.role = 'coach' and p.verified_at is null;

-- ---------- certifications ----------
create table if not exists public.coach_certifications (
  id           uuid primary key default gen_random_uuid(),
  coach_id     uuid not null references public.profiles(id) on delete cascade,
  title        text not null,
  issuer       text,
  cert_date    date,
  file_path    text,
  status       text not null default 'pending' check (status in ('pending','approved','rejected')),
  note         text,
  submitted_at timestamptz not null default now(),
  reviewed_at  timestamptz,
  reviewed_by  uuid references public.profiles(id) on delete set null
);
alter table public.coach_certifications enable row level security;

drop policy if exists "coach manages own certifications" on public.coach_certifications;
create policy "coach manages own certifications" on public.coach_certifications
  for all to authenticated using (coach_id = auth.uid()) with check (coach_id = auth.uid());

drop policy if exists "approved certifications are public" on public.coach_certifications;
create policy "approved certifications are public" on public.coach_certifications
  for select to authenticated using (status = 'approved');

drop policy if exists "admin reads all certifications" on public.coach_certifications;
create policy "admin reads all certifications" on public.coach_certifications
  for select to authenticated using (exists (select 1 from public.profiles where id = auth.uid() and is_admin));

-- admins need to open the attached files
drop policy if exists "admin reads all videos" on storage.objects;
create policy "admin reads all videos" on storage.objects
  for select to authenticated
  using (bucket_id = 'videos' and exists (select 1 from public.profiles where id = auth.uid() and is_admin));

-- ---------- admin: assign badges in one call ----------
create or replace function public.admin_set_badges(
  p_coach uuid, p_professional boolean default null, p_employer text default null, p_founding boolean default null
)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin boolean;
  v_row public.profiles;
  v_cur text;
begin
  select is_admin into v_admin from public.profiles where id = auth.uid();
  if not coalesce(v_admin,false) then raise exception 'admin only'; end if;
  select pro_status into v_cur from public.profiles where id = p_coach and role = 'coach';
  if v_cur is null then raise exception 'not a coach'; end if;

  if p_professional is not null then
    -- Certified is earned through a certification, not toggled here; only move between none <-> professional
    if p_professional and v_cur <> 'certified' then
      update public.profiles set pro_status = 'professional' where id = p_coach;
    elsif not p_professional and v_cur = 'professional' then
      update public.profiles set pro_status = 'none' where id = p_coach;
    end if;
  end if;
  if p_employer is not null then
    update public.profiles set pro_employer = nullif(trim(p_employer),'') where id = p_coach;
  end if;
  if p_founding is not null then
    update public.profiles set founding_at = case when p_founding then coalesce(founding_at, now()) else null end where id = p_coach;
  end if;
  select * into v_row from public.profiles where id = p_coach;
  return v_row;
end;
$$;
revoke execute on function public.admin_set_badges(uuid, boolean, text, boolean) from public;
grant  execute on function public.admin_set_badges(uuid, boolean, text, boolean) to authenticated;

-- ---------- admin: approve / reject a certification ----------
create or replace function public.admin_review_certification(p_id uuid, p_approve boolean, p_note text default null)
returns public.coach_certifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin boolean;
  v_row public.coach_certifications;
begin
  select is_admin into v_admin from public.profiles where id = auth.uid();
  if not coalesce(v_admin,false) then raise exception 'admin only'; end if;
  update public.coach_certifications
     set status = case when p_approve then 'approved' else 'rejected' end,
         note = coalesce(p_note, note), reviewed_at = now(), reviewed_by = auth.uid()
   where id = p_id returning * into v_row;
  if not found then raise exception 'certification not found'; end if;
  if p_approve then
    update public.profiles set pro_status = 'certified' where id = v_row.coach_id;
  elsif not exists (select 1 from public.coach_certifications where coach_id = v_row.coach_id and status = 'approved') then
    -- no approved certification left: fall back to professional if an employer is set, else none
    update public.profiles set pro_status = case when pro_employer is not null then 'professional' else 'none' end
     where id = v_row.coach_id and pro_status = 'certified';
  end if;
  return v_row;
end;
$$;
revoke execute on function public.admin_review_certification(uuid, boolean, text) from public;
grant  execute on function public.admin_review_certification(uuid, boolean, text) to authenticated;

-- ---------- referral tiers: Referrer -> Recruiter ----------
create or replace function public.referral_stats(p_user uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with r as (
    select p.id,
           exists (select 1 from public.engagements e where e.trainee_id = p.id and e.status = 'completed') as qualified
      from public.profiles p where p.referred_by = p_user
  ),
  c as (
    select count(*)::int as signups, count(*) filter (where qualified)::int as qualified from r
  )
  select jsonb_build_object(
    'signups',   c.signups,
    'qualified', c.qualified,
    'tier',      case when c.qualified >= 25 then 3 when c.qualified >= 10 then 2 when c.qualified >= 3 then 1 else 0 end,
    'title',     case when c.qualified >= 25 then 'Partner' when c.qualified >= 10 then 'Ambassador' when c.qualified >= 3 then 'Recruiter' else null end,
    'next_at',   case when c.qualified >= 25 then null when c.qualified >= 10 then 25 when c.qualified >= 3 then 10 else 3 end
  ) from c;
$$;

select 'coaches with verified_at' as check, count(*) from public.profiles where role='coach' and verified_at is not null;
