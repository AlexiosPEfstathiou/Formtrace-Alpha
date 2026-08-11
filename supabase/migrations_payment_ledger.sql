-- =====================================================================
-- FormTrace — payment cadence: structured rate, ledger, weekly cycles
-- Run in the Supabase SQL editor.
--
-- DISPLAY / ACCOUNTING ONLY. No money moves. This computes and stores
-- exactly what is owed, to whom, and why, so the UI can show it honestly.
-- Settlement (an actual payment provider) is a separate, later piece of
-- work — explicitly deferred per the product log.
--
-- WHY offers.price_text CANNOT BE BILLED FROM
--   It is free text ("£25/session", "ask me"). Charging requires a real
--   number, so this adds structured fields ALONGSIDE it. price_text is not
--   touched or removed — it stays as the coach's own framing of the same
--   number, shown together with the structured amount rather than instead
--   of it.
--
-- THE TWO BILLING EVENTS ARE DELIBERATELY SEPARATE
--   1. Coach earnings: rate_per_workout x workouts REVIEWED before the
--      review deadline for that cycle. Never triggered by performing a
--      workout alone.
--   2. Trainee no-show fee: noshow_fraction x rate_per_workout, per missed
--      workout, independent of review. A trainee can owe this in the same
--      cycle a coach earns nothing, or the reverse.
--   These are UNION'd into one ledger table with a `kind` column rather
--   than two tables, because both are "a charge attached to one assigned
--   workout, in one cycle" and every downstream query (weekly totals, the
--   coach summary, a trainee's statement) wants them together.
--
-- CYCLE MECHANICS
--   Weeks are Monday-start, matching weekStartISO() in the client. Workout
--   W, due in week N, is billable in week N's cycle. Week N's payment RUNS
--   at the end of week N+1 — one cycle of float, per the interview. So:
--     review_deadline(week N) = end of week N+1 = the payment date
--   A workout reviewed after its own week's deadline is not lost outright —
--   the log entry supports it landing in whichever LATER cycle it was
--   actually reviewed in, judged against THAT cycle's deadline. This
--   migration builds the ledger and the deadline math; it does not yet
--   run an actual payout job, since there is no provider to pay out to.
--
-- A workout that is postponed simply carries its CURRENT due_date — there is
-- no "originally due" tracking, per the interview. The ledger only ever
-- looks at due_date at query time, so a reschedule already does the right
-- thing with zero extra code.
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 1 — structured pricing on the offer
-- ---------------------------------------------------------------------
alter table public.offers
  add column if not exists rate_per_workout_cents integer,
  add column if not exists noshow_fraction_pct    smallint,   -- 0-100, e.g. 50 = half rate
  add column if not exists workouts_per_week_cap   integer;    -- protects the trainee from being billed beyond what was agreed

do $$
begin
  if not exists (select 1 from pg_constraint where conname='offers_rate_nonneg_chk') then
    alter table public.offers add constraint offers_rate_nonneg_chk
      check (rate_per_workout_cents is null or rate_per_workout_cents >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname='offers_noshow_pct_chk') then
    alter table public.offers add constraint offers_noshow_pct_chk
      check (noshow_fraction_pct is null or noshow_fraction_pct between 0 and 100);
  end if;
  if not exists (select 1 from pg_constraint where conname='offers_cap_pos_chk') then
    alter table public.offers add constraint offers_cap_pos_chk
      check (workouts_per_week_cap is null or workouts_per_week_cap > 0);
  end if;
end $$;

-- these become required for NEW offers once the offer-builder UI collects
-- them; existing offers keep NULL rather than being force-filled, and the
-- UI must treat NULL as "no structured pricing yet" rather than free
comment on column public.offers.rate_per_workout_cents is
  'Integer minor units (pence/cents). NULL on offers created before this migration.';

-- ---------------------------------------------------------------------
-- PART 2 — the ledger
-- ---------------------------------------------------------------------
create table if not exists public.payment_ledger (
  id            uuid primary key default gen_random_uuid(),
  engagement_id uuid not null references public.engagements(id) on delete cascade,
  assigned_id   uuid not null references public.assigned_workouts(id) on delete cascade,
  kind          text not null check (kind in ('review_earning','noshow_fee')),
  cycle_start   date not null,   -- Monday of the week this charge belongs to
  amount_cents  integer not null check (amount_cents >= 0),
  status        text not null default 'pending' check (status in ('pending','payable','expired','paid')),
  -- 'pending'  : cycle still open, outcome not yet final
  -- 'payable'  : reviewed inside its deadline (review_earning) or the
  --              missed workout is confirmed (noshow_fee) — will be paid
  --              on the NEXT payout run once one exists
  -- 'expired'  : review_earning only — the deadline passed unreviewed;
  --              this specific charge can never become payable again
  -- 'paid'     : included in a completed payout (future work; unused today)
  created_at    timestamptz not null default now(),
  decided_at    timestamptz,
  unique (assigned_id, kind)   -- one earning row and one fee row per workout, max
);

alter table public.payment_ledger enable row level security;

drop policy if exists "parties read own ledger" on public.payment_ledger;
create policy "parties read own ledger"
  on public.payment_ledger for select to authenticated
  using (
    exists (select 1 from public.engagements e
            where e.id = payment_ledger.engagement_id
              and (e.coach_id = auth.uid() or e.trainee_id = auth.uid()))
  );
-- no client INSERT/UPDATE policy: the ledger is written only by the
-- SECURITY DEFINER functions below, so its numbers cannot be forged by
-- either party.

create index if not exists payment_ledger_cycle_idx on public.payment_ledger (engagement_id, cycle_start);

-- ---------------------------------------------------------------------
-- PART 3 — cycle math
-- ---------------------------------------------------------------------
-- Monday of the week containing p_date. Matches weekStartISO() in the client.
create or replace function public.cycle_start_of(p_date date)
returns date language sql immutable as $$
  select p_date - ((extract(isodow from p_date)::int - 1));
$$;

-- Week N's payment date = end of week N+1 = the Sunday after next.
create or replace function public.cycle_payment_date(p_cycle_start date)
returns date language sql immutable as $$
  select p_cycle_start + 13;   -- +7 to next Monday, +6 to that week's Sunday
$$;

-- ---------------------------------------------------------------------
-- PART 4 — recompute the ledger for one engagement
--   Idempotent: safe to call repeatedly (e.g. on every homepage load, or
--   from a scheduled job once one exists). Never downgrades a 'paid' row.
-- ---------------------------------------------------------------------
create or replace function public.recompute_ledger(p_engagement uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  eng record;
  today date := current_date;
  aw record;
  cyc date;
  deadline date;
  final boolean;
begin
  select e.*, o.rate_per_workout_cents, o.noshow_fraction_pct
    into eng
  from public.engagements e
  left join public.offers o on o.id = e.offer_id
  where e.id = p_engagement;
  if eng.id is null then return; end if;
  if eng.rate_per_workout_cents is null then return; end if;   -- no structured pricing on this offer

  for aw in
    select a.id, a.status,
           coalesce(a.due_date, (a.created_at at time zone 'UTC')::date) as d
    from public.assigned_workouts a
    where a.engagement_id = p_engagement
  loop
    cyc := public.cycle_start_of(aw.d);
    deadline := public.cycle_payment_date(cyc);
    final := (today > deadline);   -- past its own deadline; outcome is settled

    -- review earning: only if reviewed, valued at the rate agreed
    if aw.status = 'reviewed' then
      insert into public.payment_ledger (engagement_id, assigned_id, kind, cycle_start, amount_cents, status, decided_at)
      values (p_engagement, aw.id, 'review_earning', cyc, eng.rate_per_workout_cents,
              case when today <= deadline then 'payable' else 'payable' end, now())
      on conflict (assigned_id, kind) do update
        set amount_cents = excluded.amount_cents,
            status = case when public.payment_ledger.status = 'paid' then public.payment_ledger.status else excluded.status end,
            decided_at = coalesce(public.payment_ledger.decided_at, excluded.decided_at);
    elsif final and aw.status in ('assigned','submitted') then
      -- performed-but-unreviewed OR never-submitted, and the deadline for
      -- THIS workout's cycle has passed: no earning is possible any more
      insert into public.payment_ledger (engagement_id, assigned_id, kind, cycle_start, amount_cents, status, decided_at)
      values (p_engagement, aw.id, 'review_earning', cyc, eng.rate_per_workout_cents, 'expired', now())
      on conflict (assigned_id, kind) do update
        set status = case when public.payment_ledger.status = 'paid' then public.payment_ledger.status else 'expired' end,
            decided_at = coalesce(public.payment_ledger.decided_at, now());
    end if;

    -- no-show fee: workout still 'assigned' (never submitted) and its own
    -- due date has passed — independent of review entirely
    if aw.status = 'assigned' and aw.d < today and eng.noshow_fraction_pct is not null then
      insert into public.payment_ledger (engagement_id, assigned_id, kind, cycle_start, amount_cents, status, decided_at)
      values (p_engagement, aw.id, 'noshow_fee', cyc,
              round(eng.rate_per_workout_cents * eng.noshow_fraction_pct / 100.0)::int,
              'payable', now())
      on conflict (assigned_id, kind) do nothing;   -- fee is fixed at the moment it's confirmed; never revalued
    end if;
  end loop;
end;
$$;

revoke execute on function public.recompute_ledger(uuid) from public;
grant  execute on function public.recompute_ledger(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- PART 5 — coach's per-trainee summary, per the requested layout:
--   rate agreed · cap agreed · reviewed-pending count · computed total
-- ---------------------------------------------------------------------
create or replace function public.coach_payment_summary(p_coach uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare out jsonb;
begin
  if p_coach <> auth.uid() then raise exception 'not authorised'; end if;
  select coalesce(jsonb_agg(row), '[]'::jsonb) into out
  from (
    select jsonb_build_object(
      'engagement_id',     e.id,
      'trainee_name',      public.public_name(p.display_name, coalesce(p.name_style,'first')),
      'rate_per_workout_cents', o.rate_per_workout_cents,
      'workouts_per_week_cap',  o.workouts_per_week_cap,
      'noshow_fraction_pct',    o.noshow_fraction_pct,
      'reviewed_pending_count', (select count(*) from public.payment_ledger l
                                  where l.engagement_id = e.id and l.kind='review_earning' and l.status='payable'),
      'reviewed_pending_cents', (select coalesce(sum(amount_cents),0) from public.payment_ledger l
                                  where l.engagement_id = e.id and l.kind='review_earning' and l.status='payable'),
      'noshow_pending_cents',   (select coalesce(sum(amount_cents),0) from public.payment_ledger l
                                  where l.engagement_id = e.id and l.kind='noshow_fee' and l.status='payable'),
      'next_payment_date',      (select min(public.cycle_payment_date(l.cycle_start)) from public.payment_ledger l
                                  where l.engagement_id = e.id and l.status='payable')
    ) as row
    from public.engagements e
    join public.profiles p on p.id = e.trainee_id
    left join public.offers o on o.id = e.offer_id
    where e.coach_id = p_coach and e.status = 'active'
  ) s;
  return out;
end;
$$;

revoke execute on function public.coach_payment_summary(uuid) from public;
grant  execute on function public.coach_payment_summary(uuid) to authenticated;

select proname from pg_proc
where proname in ('cycle_start_of','cycle_payment_date','recompute_ledger','coach_payment_summary')
order by proname;
