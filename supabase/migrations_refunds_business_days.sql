-- =====================================================================
-- FormTrace – DZ part 3: the coach's review window is 5 BUSINESS days (owner, 2026-10-30),
-- replacing the 72-hour rule. Business days = Monday to Friday (public holidays ignored).
-- Run AFTER migrations_refunds_evidence.sql. Safe to re-run.
-- =====================================================================

insert into public.platform_rates (key, value, note) values
  ('review_window_business_days', 5, 'DZ/terms: business days (Mon-Fri) a coach has to review a submitted session; beyond this = evidence of coach failure')
on conflict (key) do nothing;
update public.platform_rates set note = 'superseded 2026-10-30 by review_window_business_days' where key = 'review_window_hours';

-- the deadline: n business days after a timestamp (same clock time), skipping Sat/Sun
create or replace function public.add_business_days(p_from timestamptz, p_days integer)
returns timestamptz language plpgsql immutable as $$
declare d timestamptz := p_from; n integer := 0;
begin
  while n < p_days loop
    d := d + interval '1 day';
    if extract(isodow from d) < 6 then n := n + 1; end if;
  end loop;
  return d;
end $$;

create or replace function public.queue_refund(p_eng uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  e record; v_weekly bigint; v_price bigint; v_released bigint; v_unreleased bigint;
  v_rule text; v_refund_price bigint; v_proc bigint; v_amount bigint; v_week_start date;
  v_claimed boolean; v_evidence boolean := false; v_flag boolean := false; v_note text := null;
  v_days integer := coalesce((select value::int from platform_rates where key = 'review_window_business_days'), 5);
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

  -- evidence: a submitted session whose review deadline (5 business days) has passed unreviewed
  v_claimed := e.end_reason in ('coach_unresponsive','quality','no_payment_details');
  if v_claimed then
    select exists (
      select 1 from assigned_workouts aw join submissions s on s.assigned_id = aw.id
       where aw.engagement_id = p_eng and aw.status = 'submitted'
         and public.add_business_days(s.created_at, v_days) < now()) into v_evidence;
    if not v_evidence then
      v_flag := true;
      v_note := 'trainee gave reason "' || coalesce(e.end_reason,'') || '" but every submitted session was within its '
                || v_days || '-business-day review window - treated as trainee_stopped; owner may top up the week in progress by hand';
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

-- check: expect days 5, and the helper: Friday 12:00 + 5 business days = the following Friday
select (select value from public.platform_rates where key = 'review_window_business_days') as days,
       public.add_business_days('2026-10-30 12:00+00'::timestamptz, 5) as fri_plus_5;
