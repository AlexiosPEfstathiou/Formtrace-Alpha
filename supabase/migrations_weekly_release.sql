-- =====================================================================
-- FormTrace – Item DY: weekly releases – each delivered week paid to the coach.
-- Owner rules (2026-10-30): a week is DELIVERED when it has closed AND the coach has
-- reviewed every session the trainee submitted in it; release after a 14-day HOLD from
-- the close. Comp deposits (ED, deposit_amount = 0) move the steps without money.
-- Neutral weeks (no sessions / paused) are not released; the money stays in the deposit
-- for DZ (decision to confirm with the coaches).
-- Pattern: pg_cron -> queue_weekly_releases() inserts 'queued' rows; a Database Webhook on
-- payment_releases (INSERT + UPDATE) calls the release-send Edge Function (like push_outbox).
-- Safe to re-run.
-- =====================================================================

create table if not exists public.payment_releases (
  id                 uuid primary key default gen_random_uuid(),
  engagement_id      uuid not null references public.engagements(id) on delete cascade,
  week_start         date not null,                       -- Monday of the delivered week
  gross_cents        bigint not null,                     -- the week's price (weekly rate)
  commission_cents   bigint not null default 0,           -- FormTrace's share (0 for Founding coaches)
  amount_cents       bigint not null,                     -- what the coach receives
  currency           text not null,
  status             text not null default 'queued' check (status in ('queued','sent','failed','skipped')),
  -- queued  : waiting for release-send (or for the coach to finish Stripe onboarding)
  -- sent    : Stripe Transfer created
  -- failed  : Stripe refused; error holds the reason; retried by hand
  -- skipped : nothing to move (comp deposit)
  stripe_transfer_id text,
  error              text,
  attempts           integer not null default 0,
  nudged_at          timestamptz,                         -- last "finish your Stripe setup" push
  created_at         timestamptz not null default now(),
  sent_at            timestamptz,
  unique (engagement_id, week_start)
);
alter table public.payment_releases enable row level security;
drop policy if exists "parties read own releases" on public.payment_releases;
create policy "parties read own releases" on public.payment_releases for select to authenticated
  using (exists (select 1 from public.engagements e where e.id = payment_releases.engagement_id
                 and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())));
-- no client write policy: written by queue_weekly_releases (below) and release-send (service role)
create index if not exists payment_releases_eng_idx on public.payment_releases (engagement_id, week_start);
create index if not exists payment_releases_status_idx on public.payment_releases (status) where status = 'queued';

-- Hold period and the "every submitted session reviewed" rule live here, in one place.
insert into public.platform_rates (key, value, note) values
  ('release_hold_days', 14, 'DY: days after a week closes before its release to the coach (owner, 2026-10-30)')
on conflict (key) do nothing;

create or replace function public.queue_weekly_releases()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_hold   integer := coalesce((select value::int from platform_rates where key = 'release_hold_days'), 14);
  v_comm   numeric := coalesce((select value from platform_rates where key = 'coach_commission_pct'), 0);
  v_n      integer := 0;
  r        record;
  v_gross  bigint; v_comm_c bigint; v_amount bigint; v_released bigint; v_cap bigint;
begin
  for r in
    select e.id as engagement_id, e.coach_id, e.deposit_amount, e.deposit_processing, e.deposit_currency,
           o.rate_per_workout_cents as weekly_cents, wc.week_start, wc.neutral,
           (p.founding_at is not null) as founding
      from engagements e
      join offers o on o.id = e.offer_id
      join profiles p on p.id = e.coach_id
      join week_closures wc on wc.engagement_id = e.id
     where e.deposit_at is not null                                          -- paid through Stripe (or comp)
       and e.status in ('active','completed','ended')
       and wc.closed_at <= now() - make_interval(days => v_hold)             -- the hold has passed
       and wc.week_start >= (e.deposit_at at time zone 'UTC')::date - 6      -- not before the deposit's week
       and not exists (select 1 from payment_releases pr where pr.engagement_id = e.id and pr.week_start = wc.week_start)
       and not exists (select 1 from assigned_workouts aw                   -- DELIVERED: nothing submitted and unreviewed
                        where aw.engagement_id = e.id and aw.status = 'submitted'
                          and aw.due_date between wc.week_start and wc.week_start + 6)
     order by e.id, wc.week_start
  loop
    if r.neutral or coalesce(r.weekly_cents, 0) <= 0 then
      continue;                                                              -- neutral week: no release, money stays for DZ
    end if;
    v_gross := r.weekly_cents;
    if coalesce(r.deposit_amount, 0) = 0 then                                -- ED comp: the step moves, no money
      insert into payment_releases (engagement_id, week_start, gross_cents, commission_cents, amount_cents, currency, status, sent_at)
      values (r.engagement_id, r.week_start, v_gross, 0, 0, coalesce(r.deposit_currency, 'eur'), 'skipped', now());
      v_n := v_n + 1; continue;
    end if;
    v_comm_c  := case when r.founding then 0 else round(v_gross * v_comm / 100) end;
    v_amount  := v_gross - v_comm_c;
    -- never release more than the price part of the deposit (processing line excluded, EA)
    select coalesce(sum(gross_cents), 0) into v_released from payment_releases
     where engagement_id = r.engagement_id and status in ('queued','sent');
    v_cap := r.deposit_amount - coalesce(r.deposit_processing, 0) - v_released;
    if v_cap <= 0 then continue; end if;
    if v_gross > v_cap then v_gross := v_cap; v_comm_c := case when r.founding then 0 else round(v_gross * v_comm / 100) end; v_amount := v_gross - v_comm_c; end if;
    insert into payment_releases (engagement_id, week_start, gross_cents, commission_cents, amount_cents, currency)
    values (r.engagement_id, r.week_start, v_gross, v_comm_c, v_amount, r.deposit_currency);
    v_n := v_n + 1;
  end loop;

  -- re-fire the webhook once a day for releases still waiting on the coach's Stripe onboarding
  update payment_releases set attempts = attempts
   where status = 'queued' and error is not null and created_at < now() - interval '1 day'
     and (nudged_at is null or nudged_at < now() - interval '1 day');
  return v_n;
end $$;
revoke execute on function public.queue_weekly_releases() from public;

-- daily at 09:10 UTC, after the week-close job has run (pg_cron must be enabled - it is, DI)
select cron.unschedule('formtrace-weekly-release') where exists (select 1 from cron.job where jobname = 'formtrace-weekly-release');
select cron.schedule('formtrace-weekly-release', '10 9 * * *', $$select public.queue_weekly_releases();$$);

-- check: expect table 1, job 1, hold 14
select (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'payment_releases') as "table",
       (select count(*) from cron.job where jobname = 'formtrace-weekly-release') as job,
       (select value from public.platform_rates where key = 'release_hold_days') as hold;
