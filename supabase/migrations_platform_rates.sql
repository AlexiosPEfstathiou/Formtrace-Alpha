-- =====================================================================
-- FormTrace — Item BI groundwork: platform rates as SERVER truth.
-- Run in the Supabase SQL editor. No money moves; this is the table the
-- payment integration will read, and the app now displays from it.
--
-- Defaults (BI decision 2, 2026-09-14): trainee service fee 5.9% with a
-- minimum of 1.00 per weekly charge; coach commission 11.9%.
-- Overrides, resolved in this order: an explicit per-coach override row
-- > Founding coach (0%) > referral tier (Partner 5.9%, Ambassador 8.9%)
-- > default. effective_rates(coach) is the single place that decides.
-- =====================================================================
create table if not exists public.platform_rates (
  key   text primary key,
  value numeric not null,
  note  text,
  updated_at timestamptz not null default now()
);
insert into public.platform_rates (key, value, note) values
  ('trainee_fee_pct',      5.9,  'service fee on top of the coach price; covers card processing'),
  ('trainee_fee_min',      1.00, 'minimum service fee per weekly charge, in the offer currency'),
  ('coach_commission_pct', 11.9, 'default commission taken from the coach payout'),
  ('commission_ambassador', 8.9, 'coach commission at referral tier Ambassador (10 qualified)'),
  ('commission_partner',    5.9, 'coach commission at referral tier Partner (25 qualified)'),
  ('commission_founding',   0.0, 'coach commission for Founding coaches')
on conflict (key) do nothing;
alter table public.platform_rates enable row level security;
drop policy if exists "rates are public" on public.platform_rates;
create policy "rates are public" on public.platform_rates for select to authenticated using (true);

-- explicit per-coach override (admin-set), beats every rule
create table if not exists public.fee_overrides (
  coach_id             uuid primary key references public.profiles(id) on delete cascade,
  coach_commission_pct numeric not null check (coach_commission_pct between 0 and 100),
  reason               text,
  set_by               uuid references public.profiles(id) on delete set null,
  set_at               timestamptz not null default now()
);
alter table public.fee_overrides enable row level security;
drop policy if exists "overrides are public" on public.fee_overrides;
create policy "overrides are public" on public.fee_overrides for select to authenticated using (true);

create or replace function public.admin_set_fee_override(p_coach uuid, p_pct numeric, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_admin boolean;
begin
  select is_admin into v_admin from public.profiles where id = auth.uid();
  if not coalesce(v_admin,false) then raise exception 'admin only'; end if;
  if p_pct is null then
    delete from public.fee_overrides where coach_id = p_coach;
  else
    insert into public.fee_overrides (coach_id, coach_commission_pct, reason, set_by)
    values (p_coach, p_pct, p_reason, auth.uid())
    on conflict (coach_id) do update set coach_commission_pct = excluded.coach_commission_pct, reason = excluded.reason, set_by = auth.uid(), set_at = now();
  end if;
end;
$$;
revoke execute on function public.admin_set_fee_override(uuid, numeric, text) from public;
grant  execute on function public.admin_set_fee_override(uuid, numeric, text) to authenticated;

-- the one place that decides a coach's effective rates
create or replace function public.effective_rates(p_coach uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r record;
  v_pct numeric; v_src text;
  v_over numeric; v_founding timestamptz; v_tier int;
begin
  select
    (select value from public.platform_rates where key='trainee_fee_pct')       as fee_pct,
    (select value from public.platform_rates where key='trainee_fee_min')       as fee_min,
    (select value from public.platform_rates where key='coach_commission_pct')  as def_pct,
    (select value from public.platform_rates where key='commission_ambassador') as amb_pct,
    (select value from public.platform_rates where key='commission_partner')    as par_pct,
    (select value from public.platform_rates where key='commission_founding')   as fnd_pct
  into r;
  select coach_commission_pct into v_over from public.fee_overrides where coach_id = p_coach;
  select founding_at into v_founding from public.profiles where id = p_coach;
  v_tier := coalesce((public.referral_stats(p_coach)->>'tier')::int, 0);

  if v_over is not null then v_pct := v_over; v_src := 'override';
  elsif v_founding is not null then v_pct := r.fnd_pct; v_src := 'founding';
  elsif v_tier >= 3 then v_pct := r.par_pct; v_src := 'partner';
  elsif v_tier >= 2 then v_pct := r.amb_pct; v_src := 'ambassador';
  else v_pct := r.def_pct; v_src := 'default';
  end if;

  return jsonb_build_object(
    'trainee_fee_pct', r.fee_pct, 'trainee_fee_min', r.fee_min,
    'coach_commission_pct', v_pct, 'commission_source', v_src
  );
end;
$$;
revoke execute on function public.effective_rates(uuid) from public;
grant  execute on function public.effective_rates(uuid) to authenticated;

select key, value from public.platform_rates order by key;
