-- EJ part 3 (owner decision 2026-11-04): a card dispute CANCELS THE GOAL and every payout / refund
-- the moment it opens. If the dispute is later won (or the inquiry closes), what was cancelled
-- because of it is restored: payouts for delivered weeks go back in the queue, refunds that existed
-- before the dispute are re-issued. If it is lost, everything stays cancelled - including payouts
-- queued later (e.g. the week in progress the coach would have kept), so Formtrace never pays out
-- money the bank has already returned to the cardholder.
-- Both sides are told (owner: coach and trainee see it): push + a notice on the goal (index.html).
-- Safe to re-run.

-- 0. a new end kind
alter table public.engagements drop constraint if exists engagements_end_kind_check;
alter table public.engagements add constraint engagements_end_kind_check
  check (end_kind is null or end_kind = any (array['achieved', 'cancelled', 'coach_ended', 'disputed']));

-- 1. a goal ended by a dispute gets no automatic refund (the bank handles the money)
create or replace function public.refund_on_end() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'ended' and old.status is distinct from 'ended' and new.deposit_at is not null
     and new.end_kind is distinct from 'disputed' then
    begin
      if new.end_kind = 'coach_ended' then perform public.queue_end_choice(new.id);
      else perform public.queue_refund(new.id); end if;
    exception when others then raise warning 'refund_on_end %: %', new.id, sqlerrm; end;
  end if;
  return new;
end $$;

-- 2. a payout or refund queued while a dispute is open, or after it was lost, is cancelled at once
create or replace function public._hold_if_disputed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'queued' and (tg_op = 'INSERT' or old.status is distinct from 'queued') then
    if exists (select 1 from public.payment_disputes d
                where d.engagement_id = new.engagement_id and public._dispute_open(d.status)) then
      new.status := 'cancelled';
      new.error  := 'cancelled: card dispute open';
    elsif exists (select 1 from public.payment_disputes d
                   where d.engagement_id = new.engagement_id and d.status = 'lost') then
      new.status := 'cancelled';
      new.error  := 'dispute lost - the cardholder got the money back';
    end if;
  end if;
  return new;
end $$;

-- 3. what a dispute's state means for that goal
create or replace function public._apply_dispute_state(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare d public.payment_disputes; e public.engagements; r record;
begin
  select * into d from public.payment_disputes where id = p_id;
  if not found or d.engagement_id is null then return; end if;

  if public._dispute_open(d.status) then
    update public.payment_releases set status = 'cancelled', error = 'cancelled: card dispute open'
     where engagement_id = d.engagement_id and status in ('queued', 'held');
    update public.payment_refunds  set status = 'cancelled', error = 'cancelled: card dispute open'
     where engagement_id = d.engagement_id and status in ('queued', 'held');
    -- cancel the goal (once) and tell both sides
    update public.engagements
       set status = 'ended', end_kind = 'disputed', end_reason = coalesce(end_reason, 'card_dispute'),
           completed_at = coalesce(completed_at, now())
     where id = d.engagement_id and status = 'active'
     returning * into e;
    if found and to_regclass('public.push_outbox') is not null then
      begin
        insert into public.push_outbox (to_user, kind, title, body, url) values
          (e.coach_id, 'offer',
           'Payment disputed - goal cancelled' || case when d.livemode then '' else ' (test)' end,
           coalesce(e.goal_title, 'Goal') || ': the trainee''s bank disputed the card payment. The goal is cancelled and payouts have stopped.',
           '/#coach'),
          (e.trainee_id, 'offer',
           'Your bank disputed a payment' || case when d.livemode then '' else ' (test)' end,
           coalesce(e.goal_title, 'Your goal') || ' is cancelled. If this is a mistake, contact contact@formtrace.ie.',
           '/#listings');
      exception when others then raise warning 'EJ dispute push skipped: %', sqlerrm; end;
    end if;
    return;
  end if;

  -- another dispute on the same payment still open: change nothing yet
  if exists (select 1 from public.payment_disputes x
              where x.engagement_id = d.engagement_id and x.id <> d.id and public._dispute_open(x.status)) then
    return;
  end if;

  if d.status = 'lost' then
    update public.payment_releases set status = 'cancelled', error = 'dispute lost - the cardholder got the money back'
     where engagement_id = d.engagement_id and status in ('queued', 'held');
    update public.payment_refunds  set status = 'cancelled', error = 'dispute lost - the cardholder got the money back'
     where engagement_id = d.engagement_id and status in ('queued', 'held');
  else
    -- won, inquiry closed or prevented: restore what the dispute cancelled (the goal stays ended)
    update public.payment_releases set status = 'queued', error = null
     where engagement_id = d.engagement_id
       and (status = 'held' or (status = 'cancelled' and error = 'cancelled: card dispute open'));   -- UPDATE webhook sends them
    for r in select * from public.payment_refunds
              where engagement_id = d.engagement_id
                and (status = 'held' or (status = 'cancelled' and error = 'cancelled: card dispute open')) loop
      update public.payment_refunds set status = 'cancelled', error = 're-issued after the dispute closed' where id = r.id;
      insert into public.payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, flagged, flag_note, breakdown)
      values (r.engagement_id, r.price_cents, r.processing_cents, r.amount_cents, r.currency, r.reason, r.rule, r.flagged, r.flag_note, r.breakdown);  -- INSERT webhook -> refund-send
    end loop;
  end if;
end $$;

-- 4. evidence pack: "over 1 week", not "over 1 weeks"
do $$
declare src text;
begin
  src := pg_get_functiondef('public.admin_dispute_evidence(uuid)'::regprocedure);
  if position('(ej->>''committed_weeks'') || '' weeks''' in src) > 0 then
    src := replace(src, '(ej->>''committed_weeks'') || '' weeks''',
                   '(ej->>''committed_weeks'') || case when (ej->>''committed_weeks'') = ''1'' then '' week'' else '' weeks'' end');
    execute src;
  end if;
end $$;

-- 5. goals that already have an open dispute: cancel them now (re-applies step 3)
do $$
declare x record;
begin
  for x in select id from public.payment_disputes where public._dispute_open(status) loop
    perform public._apply_dispute_state(x.id);
  end loop;
end $$;

-- Check: expect  end_kind_ok 1 | evidence_fixed 1 | open_disputes_on_active_goals 0
select
  (select count(*) from pg_constraint where conname = 'engagements_end_kind_check'
     and pg_get_constraintdef(oid) like '%disputed%') as end_kind_ok,
  (select count(*) from pg_proc where proname = 'admin_dispute_evidence'
     and prosrc like '%then '' week'' else%') as evidence_fixed,
  (select count(*) from public.payment_disputes d join public.engagements e on e.id = d.engagement_id
    where public._dispute_open(d.status) and e.status = 'active') as open_disputes_on_active_goals;
