-- =====================================================================
-- FormTrace — payment cadence v2: proportional weekly billing
-- Run in the Supabase SQL editor. Supersedes migrations_payment_ledger.sql
-- (that file's tables/functions are replaced below, not left running
-- alongside a different model).
--
-- DISPLAY / ACCOUNTING ONLY. No money moves yet.
--
-- MODEL CHANGE FROM v1, per second interview:
--   v1 charged per workout, at the moment each one settled, so a no-show
--   fee could appear days before the coach's matching earning was known.
--   v2 charges ONE number per trainee per week, computed once, at the
--   single payment date for that week:
--
--     charge = (reviewed / agreed) * weekly_rate
--            + (missed   / agreed) * weekly_rate * noshow_fraction
--
--   where `agreed` = offers.workouts_per_week_cap and `reviewed` /
--   `missed` are counted against that week's assigned workouts. A workout
--   neither reviewed nor missed yet (still pending, due date not passed)
--   contributes to neither term — it simply isn't resolved yet.
--
--   offers.rate_per_workout_cents is renamed to WEEKLY units — the coach
--   sets one weekly figure, the per-workout share is arithmetic
--   (weekly_rate_cents / workouts_per_week_cap), never an independent
--   input. workouts_per_week_cap is now the DENOMINATOR of every fraction,
--   not a ceiling that discards extra reviews — reviewing more than
--   agreed does not increase the charge (there is nothing to divide the
--   extra by), which is the trainee-protection point 5 asked for, achieved
--   differently than v1's per-item cap did it.
--
-- CYCLE MECHANICS — unchanged from v1
--   Weeks are Monday-start (matches weekStartISO()). Week N is billed at
--   the payment date for week N = end of week N+1 (one cycle of float).
--   A rescheduled workout carries its current due_date; the ledger never
--   tracks "originally due".
-- =====================================================================

-- ---------------------------------------------------------------------
-- PART 0 — undo v1's ledger table and functions, which modelled a
-- different (per-item) charge shape. offers columns from v1 are kept and
-- reused below; nothing there needs undoing.
-- ---------------------------------------------------------------------
drop function if exists public.recompute_ledger(uuid);
drop function if exists public.coach_payment_summary(uuid);
drop table if exists public.payment_ledger;

-- ---------------------------------------------------------------------
-- PART 1 — offers: rename the mental model, not the column, to avoid a
-- second migration touching every offer row. rate_per_workout_cents now
-- HOLDS a weekly figure; the comment says so for anyone reading the schema
-- later. workouts_per_week_cap is the agreed count this is divided by.
-- ---------------------------------------------------------------------
comment on column public.offers.rate_per_workout_cents is
  'Despite the name, this is the WEEKLY rate as of the v2 payment model. Per-workout share = this / workouts_per_week_cap. NULL on offers without structured pricing.';
comment on column public.offers.workouts_per_week_cap is
  'The AGREED workouts/week — now the denominator of every proportional charge, not a ceiling. NULL means no structured pricing.';

-- ---------------------------------------------------------------------
-- PART 2 — one row per trainee per week: the whole charge, computed once.
-- ---------------------------------------------------------------------
create table if not exists public.payment_cycles (
  id              uuid primary key default gen_random_uuid(),
  engagement_id   uuid not null references public.engagements(id) on delete cascade,
  cycle_start     date not null,                 -- Monday of the billed week
  agreed_count    integer not null,              -- workouts_per_week_cap at computation time
  reviewed_count  integer not null default 0,
  missed_count    integer not null default 0,
  weekly_rate_cents integer not null,
  noshow_fraction_pct smallint not null default 0,
  reviewed_cents  integer not null default 0,    -- (reviewed/agreed) * weekly_rate, rounded
  noshow_cents    integer not null default 0,    -- (missed/agreed)   * weekly_rate * fraction, rounded
  total_cents     integer not null default 0,
  status          text not null default 'pending' check (status in ('pending','payable','paid')),
  -- 'pending' : the payment date for this cycle hasn't arrived yet
  -- 'payable' : payment date reached, total is final, awaiting a payout run
  -- 'paid'    : settled (future work; unused until a provider exists)
  payment_date    date not null,
  created_at      timestamptz not null default now(),
  decided_at      timestamptz,
  unique (engagement_id, cycle_start)
);

alter table public.payment_cycles enable row level security;

drop policy if exists "parties read own cycles" on public.payment_cycles;
create policy "parties read own cycles"
  on public.payment_cycles for select to authenticated
  using (
    exists (select 1 from public.engagements e
            where e.id = payment_cycles.engagement_id
              and (e.coach_id = auth.uid() or e.trainee_id = auth.uid()))
  );
-- no client write policy — written only by recompute_cycle below, so
-- neither party can edit their own charge.

create index if not exists payment_cycles_eng_idx on public.payment_cycles (engagement_id, cycle_start);

-- ---------------------------------------------------------------------
-- PART 3 — cycle math (same as v1)
-- ---------------------------------------------------------------------
create or replace function public.cycle_start_of(p_date date)
returns date language sql immutable as $$
  select p_date - ((extract(isodow from p_date)::int - 1));
$$;

create or replace function public.cycle_payment_date(p_cycle_start date)
returns date language sql immutable as $$
  select p_cycle_start + 13;
$$;

-- ---------------------------------------------------------------------
-- PART 4 — compute (or recompute) one engagement's charge for one week.
--   Idempotent. Before the payment date it reports a live, changeable
--   estimate ('pending'); once past it, the row is frozen ('payable').
--   A row already 'paid' is never touched.
-- ---------------------------------------------------------------------
create or replace function public.recompute_cycle(p_engagement uuid, p_cycle_start date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  eng record;
  today date := current_date;
  pay_date date := public.cycle_payment_date(p_cycle_start);
  reviewed int; missed int;
  rev_cents int; noshow int; tot int;
  existing_status text;
begin
  select e.id, o.rate_per_workout_cents as weekly_cents,
         o.workouts_per_week_cap as agreed, o.noshow_fraction_pct as pct
    into eng
  from public.engagements e
  left join public.offers o on o.id = e.offer_id
  where e.id = p_engagement;
  if eng.id is null then return; end if;
  if eng.weekly_cents is null or eng.agreed is null or eng.agreed <= 0 then return; end if;

  select status into existing_status from public.payment_cycles
    where engagement_id = p_engagement and cycle_start = p_cycle_start;
  if existing_status = 'paid' then return; end if;

  select
    count(*) filter (where a.status = 'reviewed'),
    count(*) filter (where a.status in ('assigned','submitted') and coalesce(a.due_date,(a.created_at at time zone 'UTC')::date) < today)
    into reviewed, missed
  from public.assigned_workouts a
  where a.engagement_id = p_engagement
    and public.cycle_start_of(coalesce(a.due_date,(a.created_at at time zone 'UTC')::date)) = p_cycle_start;

  rev_cents := round(eng.weekly_cents::numeric * least(reviewed, eng.agreed) / eng.agreed);
  noshow    := round(eng.weekly_cents::numeric * least(missed, eng.agreed) / eng.agreed * coalesce(eng.pct,0) / 100.0);
  tot       := rev_cents + noshow;

  insert into public.payment_cycles (
    engagement_id, cycle_start, agreed_count, reviewed_count, missed_count,
    weekly_rate_cents, noshow_fraction_pct, reviewed_cents, noshow_cents, total_cents,
    status, payment_date, decided_at
  ) values (
    p_engagement, p_cycle_start, eng.agreed, reviewed, missed,
    eng.weekly_cents, coalesce(eng.pct,0), rev_cents, noshow, tot,
    case when today >= pay_date then 'payable' else 'pending' end,
    pay_date,
    case when today >= pay_date then now() else null end
  )
  on conflict (engagement_id, cycle_start) do update
    set reviewed_count = excluded.reviewed_count,
        missed_count   = excluded.missed_count,
        reviewed_cents = excluded.reviewed_cents,
        noshow_cents   = excluded.noshow_cents,
        total_cents    = excluded.total_cents,
        status         = excluded.status,
        decided_at     = coalesce(public.payment_cycles.decided_at, excluded.decided_at);
end;
$$;

revoke execute on function public.recompute_cycle(uuid,date) from public;
grant  execute on function public.recompute_cycle(uuid,date) to authenticated;

-- convenience: recompute the last 3 weeks for one engagement in one call,
-- since a homepage load wants "am I owed anything right now" cheaply
create or replace function public.recompute_recent_cycles(p_engagement uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare wk date;
begin
  for wk in select public.cycle_start_of(current_date) - (7*n)
            from generate_series(0,2) n
  loop
    perform public.recompute_cycle(p_engagement, wk);
  end loop;
end;
$$;

revoke execute on function public.recompute_recent_cycles(uuid) from public;
grant  execute on function public.recompute_recent_cycles(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- PART 5 — coach's per-trainee summary, matching the requested layout:
-- next payment date · rate/week agreed · workouts/week agreed · reviewed
-- pending · computed total. Recomputes recent cycles first so the numbers
-- shown are always fresh, not stale from the last time someone happened
-- to call recompute.
-- ---------------------------------------------------------------------
create or replace function public.coach_payment_summary(p_coach uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare out jsonb; r record;
begin
  if p_coach <> auth.uid() then raise exception 'not authorised'; end if;

  for r in select e.id from public.engagements e where e.coach_id = p_coach and e.status = 'active'
  loop
    perform public.recompute_recent_cycles(r.id);
  end loop;

  select coalesce(jsonb_agg(row), '[]'::jsonb) into out
  from (
    select jsonb_build_object(
      'engagement_id',        e.id,
      'trainee_name',         public.public_name(p.display_name, coalesce(p.name_style,'first')),
      'weekly_rate_cents',    o.rate_per_workout_cents,
      'workouts_per_week',    o.workouts_per_week_cap,
      'noshow_fraction_pct',  o.noshow_fraction_pct,
      'current_cycle', (select jsonb_build_object(
                            'cycle_start', c.cycle_start, 'payment_date', c.payment_date,
                            'reviewed', c.reviewed_count, 'missed', c.missed_count,
                            'agreed', c.agreed_count, 'total_cents', c.total_cents,
                            'status', c.status)
                          from public.payment_cycles c
                          where c.engagement_id = e.id
                          order by c.cycle_start desc limit 1),
      'payable_total_cents', (select coalesce(sum(total_cents),0) from public.payment_cycles c
                                where c.engagement_id = e.id and c.status = 'payable'),
      'next_payment_date',    (select min(payment_date) from public.payment_cycles c
                                where c.engagement_id = e.id and c.status in ('pending','payable'))
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
where proname in ('cycle_start_of','cycle_payment_date','recompute_cycle','recompute_recent_cycles','coach_payment_summary')
order by proname;
