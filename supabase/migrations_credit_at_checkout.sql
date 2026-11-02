-- =====================================================================
-- FormTrace — FC: the trainee's credit is used at the next Checkout.
-- Credit (trainee_credits, from a coach-ended goal) comes off the price in checkout-create;
-- the deposit records it (deposit_credit_cents). Payouts use credit FIRST, paid from
-- FormTrace's balance (funding = 'credit'); then the card charge as before. If a goal partly
-- paid with credit ends early, unused credit returns as credit and only card money is
-- refunded to the card. Also: deposit_processing and deposit_credit_cents become
-- server-only, like the other deposit fields. Run AFTER
-- migrations_coach_end_goal_fast_reviews.sql. Safe to re-run.
-- =====================================================================
alter table public.engagements      add column if not exists deposit_credit_cents bigint not null default 0;
alter table public.payment_releases add column if not exists funding text not null default 'charge';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'payment_releases_funding_check') then
    alter table public.payment_releases add constraint payment_releases_funding_check check (funding in ('charge','credit'));
  end if;
end $$;
alter table public.goal_end_choices add column if not exists credit_back_cents bigint not null default 0;

-- deposit fields: written by the payment server only (now including processing and credit)
create or replace function public._guard_deposit_columns() returns trigger language plpgsql as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and (
       new.deposit_at       is distinct from old.deposit_at
    or new.deposit_amount   is distinct from old.deposit_amount
    or new.deposit_currency is distinct from old.deposit_currency
    or new.deposit_livemode is distinct from old.deposit_livemode
    or new.deposit_processing   is distinct from old.deposit_processing
    or new.deposit_credit_cents is distinct from old.deposit_credit_cents
    or new.stripe_checkout_session is distinct from old.stripe_checkout_session
    or new.stripe_payment_intent   is distinct from old.stripe_payment_intent) then
    raise exception 'deposit fields are written by the payment server only';
  end if;
  return new;
end; $$;

-- a coach-ended goal: the credit part of what is unused always returns as credit; the trainee chooses for the card part
create or replace function public.queue_end_choice(p_eng uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e record; v_card bigint; v_credit bigint; v_price bigint; v_released bigint; v_un bigint; v_cb bigint; v_card_un bigint; v_proc bigint;
begin
  select * into e from public.engagements where id = p_eng;
  if not found or e.deposit_at is null then return; end if;
  if exists (select 1 from public.goal_end_choices where engagement_id = p_eng)
     or exists (select 1 from public.payment_refunds where engagement_id = p_eng) then return; end if;
  update public.payment_releases set status = 'cancelled', error = 'goal ended by the coach'
   where engagement_id = p_eng and status = 'queued';
  if coalesce(e.deposit_amount, 0) = 0 and coalesce(e.deposit_credit_cents, 0) = 0 then return; end if;   -- comp deposit
  v_card   := coalesce(e.deposit_amount, 0) - coalesce(e.deposit_processing, 0);
  v_credit := coalesce(e.deposit_credit_cents, 0);
  v_price  := v_card + v_credit;
  select coalesce(sum(gross_cents), 0) into v_released from public.payment_releases
   where engagement_id = p_eng and status in ('sent','skipped');
  v_un := greatest(0, v_price - v_released);
  if v_un = 0 then return; end if;
  v_cb      := least(v_un, greatest(0, v_credit - v_released));                -- unused credit (payouts use credit first)
  v_card_un := v_un - v_cb;                                                     -- unused card money
  v_proc    := case when v_card > 0 then round(coalesce(e.deposit_processing, 0) * v_card_un::numeric / v_card) else 0 end;
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
revoke execute on function public.queue_end_choice(uuid) from public;

create or replace function public._apply_end_choice(p_eng uuid, p_choice text, p_by text) returns void
language plpgsql security definer set search_path = public as $$
declare c record;
begin
  select * into c from public.goal_end_choices where engagement_id = p_eng for update;
  if not found or c.status <> 'pending' then return; end if;
  if p_choice = 'credit' then
    insert into public.trainee_credits (trainee_id, amount_cents, currency, source_engagement, note)
    values (c.trainee_id, c.price_cents + c.processing_cents + coalesce(c.credit_back_cents, 0), c.currency, p_eng,
            case when p_by = 'default' then 'coach ended the goal - no choice in 14 days, kept as credit' else 'coach ended the goal - kept as credit' end);
  elsif p_choice = 'refund' then
    insert into public.payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at)
    values (p_eng, c.price_cents, 0, c.price_cents, c.currency, 'coach_ended', 'coach_ended',
            case when c.price_cents > 0 then 'queued' else 'skipped' end, case when c.price_cents > 0 then null else now() end);
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
revoke execute on function public._apply_end_choice(uuid, text, text) from public;

-- the refund rule: copied from migrations_refunds_business_days.sql; FC changes marked
create or replace function public.queue_refund(p_eng uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare
  e record; v_card bigint; v_credit bigint; v_credit_back bigint := 0; v_weekly bigint; v_price bigint; v_released bigint; v_unreleased bigint;
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

  if coalesce(e.deposit_amount, 0) = 0 and coalesce(e.deposit_credit_cents, 0) = 0 then   -- FC: a credit-funded goal is not comp
    insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at)
    values (p_eng, 0, 0, 0, coalesce(e.deposit_currency,'eur'), e.end_reason, 'comp', 'skipped', now());
    return 0;
  end if;

  v_weekly := coalesce(e.weekly_cents, 0);
  v_card   := e.deposit_amount - coalesce(e.deposit_processing, 0);             -- FC: the card part
  v_credit := coalesce(e.deposit_credit_cents, 0);                             -- FC: the credit part
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
  v_proc   := case when v_card > 0 then round(coalesce(e.deposit_processing, 0) * v_refund_price::numeric / v_card) else 0 end;
  v_amount := v_refund_price + v_proc;
  insert into payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at, flagged, flag_note)
  values (p_eng, v_refund_price, v_proc, v_amount, e.deposit_currency, e.end_reason, v_rule,
          case when v_amount > 0 then 'queued' else 'skipped' end, case when v_amount > 0 then null else now() end, v_flag, v_note);
  if v_credit_back > 0 then                                                     -- FC
    insert into trainee_credits (trainee_id, amount_cents, currency, source_engagement, note)
    values (e.trainee_id, v_credit_back, coalesce(e.deposit_currency, 'eur'), p_eng, 'goal ended early - unused credit returned');
  end if;
  return v_amount;
end $$;

revoke execute on function public.queue_refund(uuid) from public;

-- the weekly release job: copied from migrations_coach_end_goal_fast_reviews.sql; FC changes marked
create or replace function public.queue_weekly_releases()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_hold   integer := coalesce((select value::int from platform_rates where key = 'release_hold_days'), 14);
  v_fast   integer := coalesce((select value::int from platform_rates where key = 'release_hold_fast_days'), 7);   -- EL: every review within 24 h
  v_comm   numeric := coalesce((select value from platform_rates where key = 'coach_commission_pct'), 0);
  v_n      integer := 0;
  r        record;
  v_gross  bigint; v_comm_c bigint; v_amount bigint; v_released bigint; v_cap bigint;
begin
  for r in
    select e.id as engagement_id, e.coach_id, e.deposit_amount, e.deposit_processing, e.deposit_currency, e.deposit_credit_cents,
           o.rate_per_workout_cents as weekly_cents, wc.week_start, wc.neutral,
           (p.founding_at is not null) as founding
      from engagements e
      join offers o on o.id = e.offer_id
      join profiles p on p.id = e.coach_id
      join week_closures wc on wc.engagement_id = e.id
     where e.deposit_at is not null                                          -- paid through Stripe (or comp)
       and e.status in ('active','completed','ended')
       and wc.closed_at <= now() - make_interval(days => case when public.week_reviewed_fast(e.id, wc.week_start) then least(v_fast, v_hold) else v_hold end)   -- the hold has passed (EL: shorter when every review landed within 24 h)
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
    if coalesce(r.deposit_amount, 0) = 0 and coalesce(r.deposit_credit_cents, 0) = 0 then   -- ED comp: the step moves, no money (FC: credit-funded is not comp)
      insert into payment_releases (engagement_id, week_start, gross_cents, commission_cents, amount_cents, currency, status, sent_at)
      values (r.engagement_id, r.week_start, v_gross, 0, 0, coalesce(r.deposit_currency, 'eur'), 'skipped', now());
      v_n := v_n + 1; continue;
    end if;
    v_comm_c  := case when r.founding then 0 else round(v_gross * v_comm / 100) end;
    v_amount  := v_gross - v_comm_c;
    -- never release more than the price part of the deposit (processing line excluded, EA)
    select coalesce(sum(gross_cents), 0) into v_released from payment_releases
     where engagement_id = r.engagement_id and status in ('queued','sent');
    v_cap := r.deposit_amount + coalesce(r.deposit_credit_cents, 0) - coalesce(r.deposit_processing, 0) - v_released;   -- FC: credit is part of the price
    if v_cap <= 0 then continue; end if;
    if v_gross > v_cap then v_gross := v_cap; v_comm_c := case when r.founding then 0 else round(v_gross * v_comm / 100) end; v_amount := v_gross - v_comm_c; end if;
    insert into payment_releases (engagement_id, week_start, gross_cents, commission_cents, amount_cents, currency, funding)
    values (r.engagement_id, r.week_start, v_gross, v_comm_c, v_amount, r.deposit_currency,
            case when v_released < coalesce(r.deposit_credit_cents, 0) then 'credit' else 'charge' end);   -- FC: credit first, paid from the balance
    v_n := v_n + 1;
  end loop;

  -- re-fire the webhook once a day for releases still waiting on the coach's Stripe onboarding
  update payment_releases set attempts = attempts
   where status = 'queued' and error is not null and created_at < now() - interval '1 day'
     and (nudged_at is null or nudged_at < now() - interval '1 day');
  return v_n;
end $$;
revoke execute on function public.queue_weekly_releases() from public;

select (select count(*) from information_schema.columns where table_schema = 'public'
          and ((table_name = 'engagements' and column_name = 'deposit_credit_cents')
            or (table_name = 'payment_releases' and column_name = 'funding')
            or (table_name = 'goal_end_choices' and column_name = 'credit_back_cents'))) as new_columns,
       (select count(*) from pg_proc where proname in ('queue_refund','queue_weekly_releases','queue_end_choice','_apply_end_choice','_guard_deposit_columns')) as functions;