-- Item FP (owner, 2026-11-04, high priority): every refund that is not full explains what was kept and why.
-- Adds payment_refunds.breakdown (jsonb), filled by queue_refund() (trainee ended the goal) and _apply_end_choice()
-- (the trainee chose a refund after the coach ended it), and kept when a refund is re-issued after a dispute
-- (_apply_dispute_state). When a refund is not full, queue_refund() also pushes the trainee the amounts and
-- "tap to see why". The app reads the breakdown (RLS: the parties of the goal already read their refunds).
-- Fields (cents): paid_cents, paid_card_cents, paid_credit_cents, costs_cents, released_weeks, released_cents,
-- week_kept_cents, rule, reason, flagged, card_back_cents, credit_back_cents, costs_kept_cents, kept_cents, full.
-- Refunds made before this have no breakdown (the app says so). Safe to re-run.

alter table public.payment_refunds add column if not exists breakdown jsonb;
create or replace function public.queue_refund(p_eng uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  e record; v_card bigint; v_credit bigint; v_credit_back bigint := 0; v_weekly bigint; v_price bigint; v_released bigint; v_unreleased bigint;
  v_rule text; v_refund_price bigint; v_proc bigint; v_amount bigint; v_week_start date;
  v_proc_credit bigint := 0; v_proc_card bigint := 0; v_cb_proc bigint := 0;   -- FO
  v_kept_week bigint := 0; v_paid bigint := 0; v_weeks_rel integer := 0; v_kept bigint := 0; v_bd jsonb;   -- FP
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

  v_kept_week := v_unreleased - v_refund_price;   -- FP: the week in progress kept for the coach (0 if none)
  -- FC: payouts use credit first, so unreleased credit (beyond any week kept for the coach) returns as credit; only card money goes back to the card
  v_credit_back  := least(v_refund_price, greatest(0, greatest(0, v_credit - v_released) - (v_unreleased - v_refund_price)));
  v_refund_price := v_refund_price - v_credit_back;
  v_proc   := case when v_card > 0 then round(v_proc_card * v_refund_price::numeric / v_card) else 0 end;
  v_cb_proc := case when v_credit > 0 then round(v_proc_credit * v_credit_back::numeric / v_credit) else 0 end;   -- FO: its share of the payout costs
  v_amount := v_refund_price + v_proc;
  -- FP (2026-11-04): what was paid, what comes back, what is kept and why - stored with the refund, shown to the trainee
  v_paid := coalesce(e.deposit_amount, 0) + coalesce(e.deposit_credit_cents, 0);
  select count(*) into v_weeks_rel from payment_releases where engagement_id = p_eng and status in ('sent','skipped');
  v_kept := greatest(0, v_paid - v_amount - (v_credit_back + v_cb_proc));
  v_bd := jsonb_build_object(
    'currency', coalesce(e.deposit_currency, 'eur'), 'weekly_cents', v_weekly,
    'paid_cents', v_paid, 'paid_card_cents', coalesce(e.deposit_amount, 0), 'paid_credit_cents', coalesce(e.deposit_credit_cents, 0),
    'price_cents', v_price, 'costs_cents', coalesce(e.deposit_processing, 0),
    'released_weeks', v_weeks_rel, 'released_cents', v_released,
    'week_kept_cents', v_kept_week, 'rule', v_rule, 'reason', e.end_reason, 'flagged', v_flag,
    'card_back_cents', v_amount, 'credit_back_cents', v_credit_back + v_cb_proc,
    'costs_kept_cents', greatest(0, coalesce(e.deposit_processing, 0) - v_proc - v_cb_proc),
    'kept_cents', v_kept, 'full', v_kept = 0);
  insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at, flagged, flag_note, breakdown)
  values (p_eng, v_refund_price, v_proc, v_amount, e.deposit_currency, e.end_reason, v_rule,
          case when v_amount > 0 then 'queued' else 'skipped' end, case when v_amount > 0 then null else now() end, v_flag, v_note, v_bd);
  if v_credit_back + v_cb_proc > 0 then                                         -- FC (+ FO: payout-cost share)
    insert into trainee_credits (trainee_id, amount_cents, currency, source_engagement, note)
    values (e.trainee_id, v_credit_back + v_cb_proc, coalesce(e.deposit_currency, 'eur'), p_eng, 'goal ended early - unused credit returned');
  end if;
  -- FP: not a full refund -> tell the trainee straight away, with the amounts (details in the app)
  if v_kept > 0 and to_regclass('public.push_outbox') is not null then
    begin
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (e.trainee_id, 'offer', 'Refund for "' || coalesce(e.goal_title, 'your goal') || '"',
              case when v_amount > 0 then public._eur(v_amount) || ' back to your card' else '' end
              || case when v_amount > 0 and v_credit_back + v_cb_proc > 0 then ' and ' else '' end
              || case when v_credit_back + v_cb_proc > 0 then public._eur(v_credit_back + v_cb_proc) || ' as credit' else '' end
              || case when v_amount + v_credit_back + v_cb_proc > 0 then '; ' else 'Nothing to refund; ' end
              || public._eur(v_kept) || ' not refunded - tap to see why.', '/#notifications');
    exception when others then raise warning 'FP refund push skipped: %', sqlerrm; end;
  end if;
  return v_amount;
end $$;

create or replace function public._apply_end_choice(p_eng uuid, p_choice text, p_by text) returns void
language plpgsql security definer set search_path = public as $$
declare c record; e2 record; v_rel bigint := 0; v_relw integer := 0; v_paid bigint := 0; v_kept bigint := 0; v_bd jsonb;   -- FP
begin
  select * into c from public.goal_end_choices where engagement_id = p_eng for update;
  if not found or c.status <> 'pending' then return; end if;
  if p_choice = 'credit' then
    insert into public.trainee_credits (trainee_id, amount_cents, currency, source_engagement, note)
    values (c.trainee_id, c.price_cents + c.processing_cents + coalesce(c.credit_back_cents, 0), c.currency, p_eng,
            case when p_by = 'default' then 'coach ended the goal - no choice in 14 days, kept as credit' else 'coach ended the goal - kept as credit' end);
  elsif p_choice = 'refund' then
    -- FP (2026-11-04): the breakdown - weeks already delivered and Stripe's card fee are what is not refunded
    select * into e2 from public.engagements where id = p_eng;
    select coalesce(sum(gross_cents), 0), count(*) into v_rel, v_relw from public.payment_releases
     where engagement_id = p_eng and status in ('sent','skipped');
    v_paid := coalesce(e2.deposit_amount, 0) + coalesce(e2.deposit_credit_cents, 0);
    v_kept := greatest(0, v_paid - c.price_cents - coalesce(c.credit_back_cents, 0));
    v_bd := jsonb_build_object('currency', c.currency,
      'paid_cents', v_paid, 'paid_card_cents', coalesce(e2.deposit_amount, 0), 'paid_credit_cents', coalesce(e2.deposit_credit_cents, 0),
      'costs_cents', coalesce(e2.deposit_processing, 0), 'released_weeks', v_relw, 'released_cents', v_rel,
      'week_kept_cents', 0, 'rule', 'coach_ended', 'reason', 'coach_ended', 'flagged', false,
      'card_back_cents', c.price_cents, 'credit_back_cents', coalesce(c.credit_back_cents, 0),
      'costs_kept_cents', greatest(0, v_kept - v_rel), 'kept_cents', v_kept, 'full', v_kept = 0);
    insert into public.payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at, breakdown)
    values (p_eng, c.price_cents, 0, c.price_cents, c.currency, 'coach_ended', 'coach_ended',
            case when c.price_cents > 0 then 'queued' else 'skipped' end, case when c.price_cents > 0 then null else now() end, v_bd);
    if coalesce(c.credit_back_cents, 0) > 0 then                                -- FC: the credit part comes back as credit either way
      insert into public.trainee_credits (trainee_id, amount_cents, currency, source_engagement, note)
      values (c.trainee_id, c.credit_back_cents, c.currency, p_eng, 'coach ended the goal - unused credit returned');
    end if;
  else
    raise exception 'choose credit or refund';
  end if;
  update public.goal_end_choices set status = p_choice, chosen_at = now(), chosen_by = p_by where engagement_id = p_eng;
  if to_regclass('public.push_outbox') is not null then
    begin
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (c.coach_id, 'offer', public._name_of(c.trainee_id) || case when p_choice = 'credit' then ' kept the unused weeks as credit' else ' chose a refund' end,
              'Weeks already released to you are unaffected.', '/#coach');
      if p_by = 'default' then
        insert into public.push_outbox (to_user, kind, title, body, url)
        values (c.trainee_id, 'offer', public._eur(c.price_cents + c.processing_cents + coalesce(c.credit_back_cents, 0)) || ' kept as credit',
                'No choice was made within 14 days - the credit goes towards your next goal.', '/#listings');
      end if;
    exception when others then raise warning '_apply_end_choice push skipped: %', sqlerrm; end;
  end if;
end; $$;

create or replace function public._apply_dispute_state(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.payment_disputes; r record;
begin
  select * into d from public.payment_disputes where id = p_id;
  if not found or d.engagement_id is null then return; end if;
  if public._dispute_open(d.status) then
    update public.payment_releases set status = 'held', error = 'held: card dispute open'
     where engagement_id = d.engagement_id and status = 'queued';
    update public.payment_refunds  set status = 'held', error = 'held: card dispute open'
     where engagement_id = d.engagement_id and status = 'queued';
    return;
  end if;
  -- another dispute on the same payment still open: keep holding
  if exists (select 1 from public.payment_disputes x
              where x.engagement_id = d.engagement_id and x.id <> d.id and public._dispute_open(x.status)) then
    return;
  end if;
  if d.status = 'lost' then
    update public.payment_releases set status = 'cancelled', error = 'dispute lost - the cardholder got the money back'
     where engagement_id = d.engagement_id and status = 'held';
    update public.payment_refunds  set status = 'cancelled', error = 'dispute lost - the cardholder got the money back'
     where engagement_id = d.engagement_id and status = 'held';
  else
    -- won, inquiry closed or prevented: carry on as before
    update public.payment_releases set status = 'queued', error = null
     where engagement_id = d.engagement_id and status = 'held';        -- the UPDATE webhook sends them
    for r in select * from public.payment_refunds where engagement_id = d.engagement_id and status = 'held' loop
      update public.payment_refunds set status = 'cancelled', error = 're-issued after the dispute closed' where id = r.id;
      insert into public.payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, flagged, flag_note, breakdown)
      values (r.engagement_id, r.price_cents, r.processing_cents, r.amount_cents, r.currency, r.reason, r.rule, r.flagged, r.flag_note, r.breakdown);  -- INSERT webhook -> refund-send
    end loop;
  end if;
end $$;

-- Check: expect  column_ok = 1 | functions = 3
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'payment_refunds' and column_name = 'breakdown') as column_ok,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('queue_refund','_apply_end_choice','_apply_dispute_state') and p.prosrc like '%breakdown%') as functions;