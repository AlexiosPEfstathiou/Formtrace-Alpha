-- Item FO (2026-11-04, owner bug): a goal paid ENTIRELY with credit, ended early, gave back no share of its payout costs.
-- Owner's test: EUR 2,511 of credit taken (EUR 2,500 price + EUR 11 payout costs, no card); trainee ended it at once with
-- "coach not responsive" and no evidence -> rule trainee_stopped (the week in progress, EUR 500, kept for the coach - by
-- design, flagged); EUR 2,000 came back, but none of the EUR 11 - about EUR 8.80 (4 of 5 weeks) should have.
-- Cause: queue_refund() and queue_end_choice() took deposit_processing as part of the CARD payment. For a full-credit goal
-- the card part was then -EUR 11 and the payout costs sat unnoticed inside the credit.
-- Fix: for a full-credit goal the payout costs count as part of the credit; the unused share returns as credit with the
-- rest. Card-paid and part-credit goals are unchanged (their processing is on the card, as before).
-- Safe to re-run (create or replace). No data is changed by running it; refunds already made stay as they are.
create or replace function public.queue_refund(p_eng uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  e record; v_card bigint; v_credit bigint; v_credit_back bigint := 0; v_weekly bigint; v_price bigint; v_released bigint; v_unreleased bigint;
  v_rule text; v_refund_price bigint; v_proc bigint; v_amount bigint; v_week_start date;
  v_proc_credit bigint := 0; v_proc_card bigint := 0; v_cb_proc bigint := 0;   -- FO
  v_claimed boolean; v_evidence boolean := false; v_flag boolean := false; v_note text := null;
  v_days integer := coalesce((select value::int from platform_rates where key = 'review_window_business_days'), 5);
begin
  select en.*, o.rate_per_workout_cents as weekly_cents into e
    from engagements en join offers o on o.id = en.offer_id where en.id = p_eng;
  if not found or e.deposit_at is null then return 0; end if;
  if exists (select 1 from payment_refunds where engagement_id = p_eng) then return 0; end if;

  update payment_releases set status = 'cancelled', error = 'goal ended'
   where engagement_id = p_eng and status = 'queued';

  if coalesce(e.deposit_amount, 0) = 0 and coalesce(e.deposit_credit_cents, 0) = 0 then   -- FC: a credit-funded goal is not comp
    insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at)
    values (p_eng, 0, 0, 0, coalesce(e.deposit_currency,'eur'), e.end_reason, 'comp', 'skipped', now());
    return 0;
  end if;

  v_weekly := coalesce(e.weekly_cents, 0);
  -- FO (2026-11-04): a goal paid ENTIRELY with credit has its payout costs inside the credit (deposit_amount = 0,
  -- deposit_processing = the payout costs, deposit_credit_cents = price + payout costs). Split them out, so the card
  -- part is never negative and the unused share of those costs comes back as credit with the rest.
  v_proc_credit := case when coalesce(e.deposit_amount, 0) = 0 then coalesce(e.deposit_processing, 0) else 0 end;
  v_proc_card   := coalesce(e.deposit_processing, 0) - v_proc_credit;
  v_card   := greatest(0, coalesce(e.deposit_amount, 0) - v_proc_card);       -- FC: the card part (price only)
  v_credit := greatest(0, coalesce(e.deposit_credit_cents, 0) - v_proc_credit);   -- FC: the credit part (price only)
  v_price  := v_card + v_credit;
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

  -- FC: payouts use credit first, so unreleased credit (beyond any week kept for the coach) returns as credit; only card money goes back to the card
  v_credit_back  := least(v_refund_price, greatest(0, greatest(0, v_credit - v_released) - (v_unreleased - v_refund_price)));
  v_refund_price := v_refund_price - v_credit_back;
  v_proc   := case when v_card > 0 then round(v_proc_card * v_refund_price::numeric / v_card) else 0 end;
  v_cb_proc := case when v_credit > 0 then round(v_proc_credit * v_credit_back::numeric / v_credit) else 0 end;   -- FO: its share of the payout costs
  v_amount := v_refund_price + v_proc;
  insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at, flagged, flag_note)
  values (p_eng, v_refund_price, v_proc, v_amount, e.deposit_currency, e.end_reason, v_rule,
          case when v_amount > 0 then 'queued' else 'skipped' end, case when v_amount > 0 then null else now() end, v_flag, v_note);
  if v_credit_back + v_cb_proc > 0 then                                         -- FC (+ FO: payout-cost share)
    insert into trainee_credits (trainee_id, amount_cents, currency, source_engagement, note)
    values (e.trainee_id, v_credit_back + v_cb_proc, coalesce(e.deposit_currency, 'eur'), p_eng, 'goal ended early - unused credit returned');
  end if;
  return v_amount;
end $$;

create or replace function public.queue_end_choice(p_eng uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e record; v_card bigint; v_credit bigint; v_price bigint; v_released bigint; v_un bigint; v_cb bigint; v_card_un bigint; v_proc bigint;
        v_proc_credit bigint := 0; v_proc_card bigint := 0; v_cb_proc bigint := 0;   -- FO
begin
  select * into e from public.engagements where id = p_eng;
  if not found or e.deposit_at is null then return; end if;
  if exists (select 1 from public.goal_end_choices where engagement_id = p_eng)
     or exists (select 1 from public.payment_refunds where engagement_id = p_eng) then return; end if;
  update public.payment_releases set status = 'cancelled', error = 'goal ended by the coach'
   where engagement_id = p_eng and status = 'queued';
  if coalesce(e.deposit_amount, 0) = 0 and coalesce(e.deposit_credit_cents, 0) = 0 then return; end if;   -- comp deposit
  -- FO (2026-11-04): a goal paid ENTIRELY with credit has its payout costs inside the credit (deposit_amount = 0,
  -- deposit_processing = the payout costs, deposit_credit_cents = price + payout costs). Split them out, so the card
  -- part is never negative and the unused share of those costs comes back as credit with the rest.
  v_proc_credit := case when coalesce(e.deposit_amount, 0) = 0 then coalesce(e.deposit_processing, 0) else 0 end;
  v_proc_card   := coalesce(e.deposit_processing, 0) - v_proc_credit;
  v_card   := greatest(0, coalesce(e.deposit_amount, 0) - v_proc_card);       -- the card part (price only)
  v_credit := greatest(0, coalesce(e.deposit_credit_cents, 0) - v_proc_credit);   -- the credit part (price only)
  v_price  := v_card + v_credit;
  select coalesce(sum(gross_cents), 0) into v_released from public.payment_releases
   where engagement_id = p_eng and status in ('sent','skipped');
  v_un := greatest(0, v_price - v_released);
  if v_un = 0 then return; end if;
  v_cb      := least(v_un, greatest(0, v_credit - v_released));                -- unused credit (payouts use credit first)
  v_card_un := v_un - v_cb;                                                     -- unused card money
  v_proc    := case when v_card > 0 then round(v_proc_card * v_card_un::numeric / v_card) else 0 end;
  v_cb_proc := case when v_credit > 0 then round(v_proc_credit * v_cb::numeric / v_credit) else 0 end;   -- FO: its share of the payout costs
  v_cb      := v_cb + v_cb_proc;                                                -- FO: returned as credit with the rest
  if v_card_un = 0 then                                                         -- all of it was credit: nothing to choose
    insert into public.trainee_credits (trainee_id, amount_cents, currency, source_engagement, note)
    values (e.trainee_id, v_cb, coalesce(e.deposit_currency, 'eur'), p_eng, 'coach ended the goal - unused credit returned');
    insert into public.goal_end_choices (engagement_id, trainee_id, coach_id, price_cents, processing_cents, credit_back_cents, currency, status, chosen_at, chosen_by)
    values (p_eng, e.trainee_id, e.coach_id, 0, 0, v_cb, coalesce(e.deposit_currency, 'eur'), 'credit', now(), 'auto');
    if to_regclass('public.push_outbox') is not null then
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (e.trainee_id, 'offer', 'Your coach ended "' || coalesce(e.goal_title, 'your goal') || '"',
              public._eur(v_cb) || ' of unused credit is back in your account for your next goal.', '/#listings');
    end if;
    return;
  end if;
  insert into public.goal_end_choices (engagement_id, trainee_id, coach_id, price_cents, processing_cents, credit_back_cents, currency)
  values (p_eng, e.trainee_id, e.coach_id, v_card_un, v_proc, v_cb, coalesce(e.deposit_currency, 'eur'));
  if to_regclass('public.push_outbox') is not null then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (e.trainee_id, 'offer', 'Your coach ended "' || coalesce(e.goal_title, 'your goal') || '"',
            'Choose: keep ' || public._eur(v_card_un + v_proc + v_cb) || ' as credit for your next goal, or a refund of ' || public._eur(v_card_un)
            || ' to your card' || case when v_cb > 0 then ' (plus ' || public._eur(v_cb) || ' back as credit)' else '' end || '. No choice in 14 days = credit.', '/#listings');
  end if;
end; $$;

-- Check: expect  fixed = 2
select count(*) as fixed from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname in ('queue_refund','queue_end_choice') and p.prosrc like '%v_proc_credit%';