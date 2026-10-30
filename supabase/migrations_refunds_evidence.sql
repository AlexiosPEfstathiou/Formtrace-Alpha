-- =====================================================================
-- FormTrace – Item DZ, part 2: evidence check for "coach failed" refunds (owner, 2026-10-30:
-- "do we have any safeguard against trainees lying?"). A coach-failure reason is honoured
-- automatically only when there is objective evidence at the moment of ending: a submitted
-- session left unreviewed for more than review_window_hours (72 h, the terms' delivery
-- window). Otherwise the ending is treated as trainee_stopped (unused weeks still refunded,
-- the week in progress stays with the coach) and the row is FLAGGED for the owner to review.
-- Run AFTER migrations_refunds.sql. Safe to re-run.
-- =====================================================================

alter table public.payment_refunds
  add column if not exists flagged boolean not null default false,       -- claimed coach failure, no evidence
  add column if not exists flag_note text;

insert into public.platform_rates (key, value, note) values
  ('review_window_hours', 72, 'DZ/terms: hours a coach has to review a submitted session; unreviewed beyond this = evidence of coach failure')
on conflict (key) do nothing;

create or replace function public.queue_refund(p_eng uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  e record; v_weekly bigint; v_price bigint; v_released bigint; v_unreleased bigint;
  v_rule text; v_refund_price bigint; v_proc bigint; v_amount bigint; v_week_start date;
  v_claimed boolean; v_evidence boolean := false; v_flag boolean := false; v_note text := null;
  v_window integer := coalesce((select value::int from platform_rates where key = 'review_window_hours'), 72);
begin
  select en.*, o.rate_per_workout_cents as weekly_cents into e
    from engagements en join offers o on o.id = en.offer_id where en.id = p_eng;
  if not found or e.deposit_at is null then return 0; end if;
  if exists (select 1 from payment_refunds where engagement_id = p_eng) then return 0; end if;

  update payment_releases set status = 'cancelled', error = 'goal ended'
   where engagement_id = p_eng and status = 'queued';

  if coalesce(e.deposit_amount, 0) = 0 then
    insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at)
    values (p_eng, 0, 0, 0, coalesce(e.deposit_currency,'eur'), e.end_reason, 'comp', 'skipped', now());
    return 0;
  end if;

  v_weekly := coalesce(e.weekly_cents, 0);
  v_price  := e.deposit_amount - coalesce(e.deposit_processing, 0);
  select coalesce(sum(gross_cents), 0) into v_released from payment_releases
   where engagement_id = p_eng and status in ('sent','skipped');
  v_unreleased := greatest(0, v_price - v_released);

  -- evidence: a submitted session the coach has not reviewed within the window
  v_claimed := e.end_reason in ('coach_unresponsive','quality','no_payment_details');
  if v_claimed then
    select exists (
      select 1 from assigned_workouts aw join submissions s on s.assigned_id = aw.id
       where aw.engagement_id = p_eng and aw.status = 'submitted'
         and s.created_at < now() - make_interval(hours => v_window)) into v_evidence;
    if not v_evidence then
      v_flag := true;
      v_note := 'trainee gave reason "' || coalesce(e.end_reason,'') || '" but every submitted session was reviewed within '
                || v_window || ' h - treated as trainee_stopped; owner may top up the week in progress by hand';
    end if;
  end if;
  v_rule := case when v_claimed and v_evidence then 'coach_failed' else 'trainee_stopped' end;

  v_refund_price := v_unreleased;
  if v_rule = 'trainee_stopped' then
    v_week_start := date_trunc('week', now() at time zone 'UTC')::date;
    if not exists (select 1 from payment_releases where engagement_id = p_eng and week_start = v_week_start and status in ('sent','skipped')) then
      v_refund_price := greatest(0, v_unreleased - v_weekly);
    end if;
  end if;

  v_proc   := case when v_price > 0 then round(coalesce(e.deposit_processing, 0) * v_refund_price::numeric / v_price) else 0 end;
  v_amount := v_refund_price + v_proc;
  insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at, flagged, flag_note)
  values (p_eng, v_refund_price, v_proc, v_amount, e.deposit_currency, e.end_reason, v_rule,
          case when v_amount > 0 then 'queued' else 'skipped' end, case when v_amount > 0 then null else now() end, v_flag, v_note);
  return v_amount;
end $$;
revoke execute on function public.queue_refund(uuid) from public;

-- owner's review list (run any time): flagged refunds, newest first
-- select pr.created_at, e.goal_title, pr.reason, pr.amount_cents, pr.flag_note from payment_refunds pr join engagements e on e.id = pr.engagement_id where pr.flagged order by 1 desc;

-- check: expect flagged_col 1, window 72
select (select count(*) from information_schema.columns where table_schema='public' and table_name='payment_refunds' and column_name='flagged') as flagged_col,
       (select value from public.platform_rates where key = 'review_window_hours') as "window";
