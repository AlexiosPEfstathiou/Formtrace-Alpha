-- Item EJ (2026-11-04): Stripe card disputes (chargebacks).
-- stripe-webhook passes every charge.dispute.* event to record_dispute(). The database then:
--   * keeps one row per dispute (an older event arriving late never overwrites a newer state);
--   * while a dispute is OPEN: holds that goal's queued payouts and refunds (status 'held');
--     release-send and refund-send only act on 'queued', so no function change is needed;
--   * WON / inquiry closed: payouts go back to 'queued' (the UPDATE webhook sends them) and
--     held refunds are re-issued as fresh rows (refund-send fires on INSERT only);
--   * LOST: held payouts and refunds are cancelled (the cardholder already got the money back);
--   * alerts every admin by push when a dispute opens and when it closes;
--   * feeds the admin card (open disputes, dispute rate, losses) and a pasteable evidence pack.
-- Safe to re-run.

-- 1. New statuses: 'held' (dispute open) on payouts and refunds; 'cancelled' on refunds
alter table public.payment_releases drop constraint if exists payment_releases_status_check;
alter table public.payment_releases add constraint payment_releases_status_check
  check (status in ('queued','sent','failed','skipped','cancelled','held'));
alter table public.payment_refunds drop constraint if exists payment_refunds_status_check;
alter table public.payment_refunds add constraint payment_refunds_status_check
  check (status in ('queued','sent','failed','skipped','cancelled','held'));

-- 2. The disputes
create table if not exists public.payment_disputes (
  id                    uuid primary key default gen_random_uuid(),
  stripe_dispute_id     text not null unique,
  stripe_charge_id      text,
  stripe_payment_intent text,
  engagement_id         uuid references public.engagements(id) on delete set null,
  amount_cents          bigint not null default 0,      -- the disputed amount
  fee_cents             bigint not null default 0,      -- Stripe's dispute fee
  currency              text,
  reason                text,                           -- Stripe's reason code, e.g. fraudulent, product_not_received
  status                text not null,                  -- Stripe's status, e.g. needs_response, under_review, won, lost
  evidence_due_by       timestamptz,
  livemode              boolean not null default false,
  funds_withdrawn_at    timestamptz,
  funds_reinstated_at   timestamptz,
  last_event_at         timestamptz,                    -- the newest Stripe event applied
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  closed_at             timestamptz
);
alter table public.payment_disputes enable row level security;
drop policy if exists payment_disputes_admin_read on public.payment_disputes;
create policy payment_disputes_admin_read on public.payment_disputes for select
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin));
-- no client write policy: written only by record_dispute() (service role, via stripe-webhook)

create or replace function public._dispute_open(p_status text) returns boolean
language sql immutable as $$
  select coalesce(p_status, '') not in ('won', 'lost', 'warning_closed', 'prevented')
$$;

-- 3. A payout or refund queued for a goal with an open dispute starts out 'held'
create or replace function public._hold_if_disputed() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'queued' and (tg_op = 'INSERT' or old.status is distinct from 'queued')
     and exists (select 1 from public.payment_disputes d
                  where d.engagement_id = new.engagement_id and public._dispute_open(d.status)) then
    new.status := 'held';
    new.error  := 'held: card dispute open';
  end if;
  return new;
end $$;
drop trigger if exists hold_if_disputed on public.payment_releases;
create trigger hold_if_disputed before insert or update of status on public.payment_releases
  for each row execute function public._hold_if_disputed();
drop trigger if exists hold_if_disputed on public.payment_refunds;
create trigger hold_if_disputed before insert or update of status on public.payment_refunds
  for each row execute function public._hold_if_disputed();

-- 4. What a dispute's state means for that goal's money
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
      insert into public.payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, flagged, flag_note)
      values (r.engagement_id, r.price_cents, r.processing_cents, r.amount_cents, r.currency, r.reason, r.rule, r.flagged, r.flag_note);  -- INSERT webhook -> refund-send
    end loop;
  end if;
end $$;

-- 5. Called by stripe-webhook (service role) for every charge.dispute.* event
create or replace function public.record_dispute(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid; v_old text; v_last timestamptz; v_new text := p->>'status';
  v_evt timestamptz := to_timestamp(coalesce((p->>'event_created')::bigint, extract(epoch from now())::bigint));
  v_eng uuid; v_title text; v_is_new boolean := false; v_live boolean := coalesce((p->>'livemode')::boolean, false);
  v_due timestamptz := case when nullif(p->>'due_by', '') is null then null else to_timestamp((p->>'due_by')::bigint) end;
  v_amt text; a record;
begin
  select id, status, last_event_at into v_id, v_old, v_last from public.payment_disputes where stripe_dispute_id = p->>'id';
  select e.id, e.goal_title into v_eng, v_title from public.engagements e
   where e.stripe_payment_intent = nullif(p->>'payment_intent', '') limit 1;
  if v_id is null then
    insert into public.payment_disputes (stripe_dispute_id, stripe_charge_id, stripe_payment_intent, engagement_id, amount_cents, fee_cents,
                                         currency, reason, status, evidence_due_by, livemode, last_event_at, closed_at)
    values (p->>'id', nullif(p->>'charge', ''), nullif(p->>'payment_intent', ''), v_eng, coalesce((p->>'amount')::bigint, 0), coalesce((p->>'fee')::bigint, 0),
            p->>'currency', p->>'reason', v_new, v_due, v_live, v_evt, case when public._dispute_open(v_new) then null else now() end)
    returning id into v_id;
    v_is_new := true;
  elsif v_last is null or v_evt >= v_last then
    update public.payment_disputes set
      status = v_new, amount_cents = coalesce((p->>'amount')::bigint, amount_cents),
      fee_cents = greatest(fee_cents, coalesce((p->>'fee')::bigint, 0)), reason = coalesce(p->>'reason', reason),
      evidence_due_by = coalesce(v_due, evidence_due_by), engagement_id = coalesce(engagement_id, v_eng),
      last_event_at = v_evt, updated_at = now(),
      closed_at = case when public._dispute_open(v_new) then null else coalesce(closed_at, now()) end
    where id = v_id;
  else
    v_new := v_old;   -- an older event arriving late: the newer state stays
  end if;
  if p->>'type' = 'charge.dispute.funds_withdrawn' then
    update public.payment_disputes set funds_withdrawn_at = coalesce(funds_withdrawn_at, now()) where id = v_id; end if;
  if p->>'type' = 'charge.dispute.funds_reinstated' then
    update public.payment_disputes set funds_reinstated_at = coalesce(funds_reinstated_at, now()) where id = v_id; end if;

  perform public._apply_dispute_state(v_id);

  -- alert every admin when a dispute opens and when it closes
  if v_is_new or (v_old is distinct from v_new and not public._dispute_open(v_new)) then
    v_amt := to_char(coalesce((p->>'amount')::bigint, 0) / 100.0, 'FM999999990.00') || ' ' || upper(coalesce(p->>'currency', 'eur'));
    for a in select id from public.profiles where is_admin loop
      insert into public.push_outbox (to_user, kind, title, body, url) values (
        a.id, 'offer',
        case when v_is_new then 'Card dispute opened' else 'Card dispute ' || replace(v_new, '_', ' ') end || case when v_live then '' else ' (test)' end,
        coalesce(v_title, 'A payment') || ' - ' || v_amt
          || case when v_is_new and v_due is not null then ' - respond in Stripe by ' || to_char(v_due, 'DD Mon') else '' end,
        '/#admin');   -- the Review tab's key is 'admin'
    end loop;
  end if;
  return v_id;
end $$;
revoke execute on function public.record_dispute(jsonb) from public, anon, authenticated;
revoke execute on function public._apply_dispute_state(uuid) from public, anon, authenticated;

-- 6. Admin card: the disputes list
create or replace function public.admin_disputes() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then raise exception 'admins only'; end if;
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.open desc, x.created_at desc) from (
      select d.id, d.stripe_dispute_id, d.stripe_payment_intent, d.amount_cents, d.fee_cents, d.currency, d.reason, d.status,
             d.evidence_due_by, d.livemode, d.created_at, d.closed_at, public._dispute_open(d.status) as open,
             e.goal_title, tp.display_name as trainee, cp.display_name as coach,
             (select count(*) from public.payment_releases r where r.engagement_id = d.engagement_id and r.status = 'held') as held_releases,
             (select coalesce(sum(r.amount_cents), 0) from public.payment_releases r where r.engagement_id = d.engagement_id and r.status = 'sent') as released_cents
        from public.payment_disputes d
        left join public.engagements e on e.id = d.engagement_id
        left join public.profiles tp on tp.id = e.trainee_id
        left join public.profiles cp on cp.id = e.coach_id
       where public._dispute_open(d.status) or d.created_at > now() - interval '180 days') x), '[]'::jsonb);
end $$;

-- 7. Evidence pack: a plain-text summary to paste into Stripe's response
create or replace function public.admin_dispute_evidence(p_id uuid) returns text
language plpgsql stable security definer set search_path = public, auth as $$
declare d public.payment_disputes; e public.engagements; ej jsonb; tj jsonb; c_name text; t_email text; t_since timestamptz;
        s text; nl text := E'\n'; r record; n int;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then raise exception 'admins only'; end if;
  select * into d from public.payment_disputes where id = p_id;
  if not found then raise exception 'dispute not found'; end if;
  select * into e from public.engagements where id = d.engagement_id;
  if not found then return 'This dispute is not linked to a FormTrace goal (payment ' || coalesce(d.stripe_payment_intent, '-') || ').'; end if;
  ej := to_jsonb(e);
  select to_jsonb(p) into tj from public.profiles p where p.id = e.trainee_id;
  select display_name into c_name from public.profiles where id = e.coach_id;
  select email, created_at into t_email, t_since from auth.users where id = e.trainee_id;

  s := 'FormTrace - evidence for Stripe dispute ' || d.stripe_dispute_id || nl
    || 'Reason given by the bank: ' || coalesce(replace(d.reason, '_', ' '), '-') || nl || nl
    || 'WHAT WAS BOUGHT' || nl
    || 'An online personal coaching programme, "' || coalesce(e.goal_title, 'goal') || '", with coach ' || coalesce(c_name, '-')
    || ', delivered inside the FormTrace web app (https://formtrace.ie)'
    || coalesce(' over ' || (ej->>'committed_weeks') || ' weeks', '') || '.' || nl
    || 'Paid: ' || to_char(coalesce((ej->>'deposit_amount')::bigint, 0) / 100.0, 'FM999999990.00') || ' ' || upper(coalesce(ej->>'deposit_currency', d.currency, 'eur'))
    || ' on ' || coalesce(to_char((ej->>'deposit_at')::timestamptz, 'DD Mon YYYY HH24:MI "UTC"'), '-') || '.' || nl
    || 'The payment is held by FormTrace and released to the coach week by week, only for weeks delivered.' || nl || nl
    || 'THE CUSTOMER' || nl
    || 'Name in the app: ' || coalesce(tj->>'display_name', '-') || nl
    || 'Account email: ' || coalesce(t_email, '-') || nl
    || 'Account created: ' || coalesce(to_char(t_since, 'DD Mon YYYY'), '-') || nl
    || 'Agreed to the terms: ' || coalesce(to_char((tj->>'consented_at')::timestamptz, 'DD Mon YYYY HH24:MI "UTC"'), '-')
    || coalesce(' (version ' || (tj->>'consent_version') || ')', '') || nl
    || 'Goal started: ' || coalesce(to_char((ej->>'started_at')::timestamptz, 'DD Mon YYYY'), '-') || nl || nl
    || 'SERVICE DELIVERED' || nl;

  select count(*) into n from public.assigned_workouts where engagement_id = e.id;
  s := s || 'Workouts assigned by the coach: ' || n || nl;
  select count(*) into n from public.submissions sb join public.assigned_workouts aw on aw.id = sb.assigned_id where aw.engagement_id = e.id;
  s := s || 'Sessions the customer recorded and submitted: ' || n || nl;
  for r in select sb.created_at from public.submissions sb join public.assigned_workouts aw on aw.id = sb.assigned_id
            where aw.engagement_id = e.id order by sb.created_at limit 40 loop
    s := s || '  - submitted ' || to_char(r.created_at, 'DD Mon YYYY HH24:MI "UTC"') || nl;
  end loop;
  select count(*) into n from public.reviews rv join public.submissions sb on sb.id = rv.submission_id
                          join public.assigned_workouts aw on aw.id = sb.assigned_id where aw.engagement_id = e.id;
  s := s || 'Coach reviews of those sessions: ' || n || nl;
  for r in select rv.created_at from public.reviews rv join public.submissions sb on sb.id = rv.submission_id
                          join public.assigned_workouts aw on aw.id = sb.assigned_id
            where aw.engagement_id = e.id order by rv.created_at limit 40 loop
    s := s || '  - reviewed ' || to_char(r.created_at, 'DD Mon YYYY HH24:MI "UTC"') || nl;
  end loop;
  select count(*) into n from public.call_proposals where engagement_id = e.id;
  if n > 0 then
    s := s || 'Coaching calls arranged: ' || n || nl;
    for r in select proposed_date, status from public.call_proposals where engagement_id = e.id order by proposed_date limit 20 loop
      s := s || '  - ' || coalesce(to_char(r.proposed_date, 'DD Mon YYYY'), '-') || ' (' || coalesce(r.status, '-') || ')' || nl;
    end loop;
  end if;
  select count(*) into n from public.payment_releases where engagement_id = e.id and status = 'sent';
  s := s || 'Weeks delivered and paid to the coach: ' || n || nl;
  for r in select status, amount_cents, currency, created_at from public.payment_refunds where engagement_id = e.id order by created_at loop
    s := s || 'Refund ' || r.status || ': ' || to_char(r.amount_cents / 100.0, 'FM999999990.00') || ' ' || upper(r.currency)
           || ' (' || to_char(r.created_at, 'DD Mon YYYY') || ')' || nl;
  end loop;
  s := s || nl || 'POLICY' || nl
    || 'Terms of service: https://formtrace.ie/terms.html - payments are held by FormTrace and released weekly only for delivered weeks; '
    || 'unused weeks are refunded or kept as credit when a goal ends early.' || nl || nl
    || 'Attach screenshots of the sessions and reviews in the app where useful.';
  return s;
end $$;

-- 8. Admin card numbers: the dispute rate and losses are now tracked
create or replace function public.admin_liability_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare m0 timestamptz := date_trunc('month', now()); q0 timestamptz := date_trunc('quarter', now()); r jsonb;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then raise exception 'admins only'; end if;
  select jsonb_build_object(
    'month_volume_cents',      coalesce((select sum(deposit_amount) from public.engagements where deposit_livemode is true  and deposit_at >= m0), 0),
    'month_volume_test_cents', coalesce((select sum(deposit_amount) from public.engagements where deposit_livemode is false and deposit_at >= m0), 0),
    'payments_month',          (select count(*) from public.engagements where deposit_livemode is true and deposit_at >= m0),
    'last3_cents', (select coalesce(jsonb_agg(v order by mo), '[]'::jsonb) from (
        select gs as mo, coalesce((select sum(e.deposit_amount) from public.engagements e
                                    where e.deposit_livemode is true and e.deposit_at >= gs and e.deposit_at < gs + interval '1 month'), 0) as v
          from generate_series(date_trunc('month', now()) - interval '2 months', date_trunc('month', now()), interval '1 month') gs) x),
    'coaches',             (select count(*) from public.profiles where role = 'coach'),
    'coaches_outside_ie',  (select count(*) from public.profiles where role = 'coach' and coalesce(upper(country_code), 'IE') <> 'IE'),
    'refunds_quarter_cents', coalesce((select sum(rf.amount_cents) from public.payment_refunds rf join public.engagements e on e.id = rf.engagement_id
                   where rf.status = 'sent' and rf.sent_at >= q0 and e.deposit_livemode is true), 0),
    'disputes_tracked',      true,
    'disputes_open',         (select count(*) from public.payment_disputes where livemode and public._dispute_open(status)),
    'disputes_open_test',    (select count(*) from public.payment_disputes where not livemode and public._dispute_open(status)),
    'disputes_month',        (select count(*) from public.payment_disputes where livemode and created_at >= m0),
    'losses_quarter_cents',  coalesce((select sum(amount_cents + fee_cents) from public.payment_disputes where livemode and status = 'lost' and closed_at >= q0), 0),
    'largest_loss_cents',    coalesce((select max(amount_cents + fee_cents) from public.payment_disputes where livemode and status = 'lost'), 0),
    'revenue_quarter_cents', coalesce((select sum(deposit_amount) from public.engagements where deposit_livemode is true and deposit_at >= q0), 0)
  ) into r;
  return r;
end; $$;

-- Check: expect  table_ok = 1 | functions = 7 | triggers = 2
select (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'payment_disputes') as table_ok,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname in ('_dispute_open','_hold_if_disputed','_apply_dispute_state','record_dispute',
                                                     'admin_disputes','admin_dispute_evidence','admin_liability_stats')) as functions,
       (select count(*) from pg_trigger where tgname = 'hold_if_disputed') as triggers;
