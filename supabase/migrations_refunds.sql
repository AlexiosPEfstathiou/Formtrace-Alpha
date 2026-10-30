-- =====================================================================
-- FormTrace – Item DZ: refunds – unreleased weeks back to the trainee when a goal ends early.
-- Rule (DK proposal, terms.html s.8, to confirm with the coaches):
--   coach failed (coach_unresponsive, quality, no_payment_details) -> every unreleased week,
--     including the week in progress, goes back to the trainee;
--   trainee stops for their own reasons -> every unreleased week except the week in progress.
-- The processing line (EA) is refunded in proportion. Queued releases are cancelled first.
-- Pattern: trigger on engagements (status -> ended) -> queue_refund() -> 'queued' row in
-- payment_refunds -> Database Webhook (INSERT) -> refund-send Edge Function -> Stripe Refund.
-- Comp deposits (ED) get a 'skipped' row so the tracker still shows the Refund step.
-- Safe to re-run.
-- =====================================================================

create table if not exists public.payment_refunds (
  id                uuid primary key default gen_random_uuid(),
  engagement_id     uuid not null references public.engagements(id) on delete cascade,
  price_cents       bigint not null,                      -- unreleased price refunded
  processing_cents  bigint not null default 0,            -- proportional share of the EA line
  amount_cents      bigint not null,                      -- price + processing = what Stripe refunds
  currency          text not null,
  reason            text,                                 -- engagements.end_reason at the time
  rule              text not null,                        -- 'coach_failed' | 'trainee_stopped'
  status            text not null default 'queued' check (status in ('queued','sent','failed','skipped')),
  stripe_refund_id  text,
  error             text,
  attempts          integer not null default 0,
  created_at        timestamptz not null default now(),
  sent_at           timestamptz
);
alter table public.payment_refunds enable row level security;
drop policy if exists "parties read own refunds" on public.payment_refunds;
create policy "parties read own refunds" on public.payment_refunds for select to authenticated
  using (exists (select 1 from public.engagements e where e.id = payment_refunds.engagement_id
                 and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())));
create index if not exists payment_refunds_eng_idx on public.payment_refunds (engagement_id);

-- releases that were queued but not yet sent are cancelled by a refund
alter table public.payment_releases drop constraint if exists payment_releases_status_check;
alter table public.payment_releases add constraint payment_releases_status_check
  check (status in ('queued','sent','failed','skipped','cancelled'));

create or replace function public.queue_refund(p_eng uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  e record; v_weekly bigint; v_price bigint; v_released bigint; v_unreleased bigint;
  v_rule text; v_refund_price bigint; v_proc bigint; v_amount bigint; v_week_start date;
begin
  select en.*, o.rate_per_workout_cents as weekly_cents into e
    from engagements en join offers o on o.id = en.offer_id where en.id = p_eng;
  if not found or e.deposit_at is null then return 0; end if;                     -- not a Stripe deposit
  if exists (select 1 from payment_refunds where engagement_id = p_eng) then return 0; end if;   -- once

  -- queued releases must not race the refund
  update payment_releases set status = 'cancelled', error = 'goal ended'
   where engagement_id = p_eng and status = 'queued';

  if coalesce(e.deposit_amount, 0) = 0 then                                        -- ED comp
    insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at)
    values (p_eng, 0, 0, 0, coalesce(e.deposit_currency,'eur'), e.end_reason, 'comp', 'skipped', now());
    return 0;
  end if;

  v_weekly := coalesce(e.weekly_cents, 0);
  v_price  := e.deposit_amount - coalesce(e.deposit_processing, 0);
  select coalesce(sum(gross_cents), 0) into v_released from payment_releases
   where engagement_id = p_eng and status in ('sent','skipped');
  v_unreleased := greatest(0, v_price - v_released);

  v_rule := case when e.end_reason in ('coach_unresponsive','quality','no_payment_details') then 'coach_failed' else 'trainee_stopped' end;
  v_refund_price := v_unreleased;
  if v_rule = 'trainee_stopped' then
    -- the week in progress stays with the coach unless it was already released
    v_week_start := date_trunc('week', now() at time zone 'UTC')::date;
    if not exists (select 1 from payment_releases where engagement_id = p_eng and week_start = v_week_start and status in ('sent','skipped')) then
      v_refund_price := greatest(0, v_unreleased - v_weekly);
    end if;
  end if;

  v_proc   := case when v_price > 0 then round(coalesce(e.deposit_processing, 0) * v_refund_price::numeric / v_price) else 0 end;
  v_amount := v_refund_price + v_proc;
  insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at)
  values (p_eng, v_refund_price, v_proc, v_amount, e.deposit_currency, e.end_reason, v_rule,
          case when v_amount > 0 then 'queued' else 'skipped' end, case when v_amount > 0 then null else now() end);
  return v_amount;
end $$;
revoke execute on function public.queue_refund(uuid) from public;

-- fires when a Stripe-paid goal is ended early; a side effect, so it never blocks the ending (rule 7)
create or replace function public.refund_on_end() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'ended' and old.status is distinct from 'ended' and new.deposit_at is not null then
    begin perform public.queue_refund(new.id); exception when others then raise warning 'refund_on_end %: %', new.id, sqlerrm; end;
  end if;
  return new;
end $$;
drop trigger if exists trg_refund_on_end on public.engagements;
create trigger trg_refund_on_end after update of status on public.engagements
  for each row execute function public.refund_on_end();

-- check: expect refunds_table 1, trigger 1, cancelled_allowed 1
select (select count(*) from information_schema.tables where table_schema='public' and table_name='payment_refunds') as refunds_table,
       (select count(*) from pg_trigger where tgname = 'trg_refund_on_end') as trigger,
       (select count(*) from pg_constraint where conname = 'payment_releases_status_check' and pg_get_constraintdef(oid) like '%cancelled%') as cancelled_allowed;
