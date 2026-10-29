-- =====================================================================
-- FormTrace — Item DU: the payment switch and coach payouts (Stripe Connect).
-- Owner decision 2026-10-29: the pilot uses Stripe escrow; go live before the pilot starts.
-- =====================================================================

-- 1. the switch: 1 = trainees pay a deposit by Stripe (escrow), the manual route disappears
--    for new goals; 0 = the earlier direct-to-coach route. Off until go-live.
insert into public.platform_rates (key, value, note)
values ('payments_via_stripe', 0, '1 = trainees pay a Stripe deposit held by FormTrace (escrow); 0 = manual direct-to-coach route')
on conflict (key) do nothing;

-- 2. each coach's Stripe connected account - NOT on profiles (profiles are broadly readable).
--    Written only by the connect-onboard Edge Function (service role); the coach can read it.
create table if not exists public.coach_stripe_accounts (
  coach_id          uuid primary key references public.profiles(id) on delete cascade,
  account_id        text not null unique,
  livemode          boolean not null default false,
  details_submitted boolean not null default false,
  payouts_enabled   boolean not null default false,
  transfers_active  boolean not null default false,
  requirements_due  integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
alter table public.coach_stripe_accounts enable row level security;
drop policy if exists "coach reads own stripe account" on public.coach_stripe_accounts;
create policy "coach reads own stripe account" on public.coach_stripe_accounts for select to authenticated using (coach_id = auth.uid());

-- 3. the only thing anyone else may know: is this coach ready to be paid?
create or replace function public.coach_payouts_ready(p_coach uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select details_submitted and transfers_active from public.coach_stripe_accounts where coach_id = p_coach), false);
$$;
revoke execute on function public.coach_payouts_ready(uuid) from public;
grant  execute on function public.coach_payouts_ready(uuid) to authenticated;

select (select value from public.platform_rates where key = 'payments_via_stripe') as payments_via_stripe,
       (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'coach_stripe_accounts') as accounts_table;
