-- Item GI-2 (security review 2026-11-10): payments that fail must not fail silently.
--   1) A payout (payment_releases) or refund (payment_refunds) whose status becomes 'failed' alerts the admins by push
--      at once - amount, goal, reason. (Before: the row was marked failed and nobody was told.)
--   2) record_refund_failure(): Stripe accepted a refund and the bank rejected it LATER (refund.failed / refund.updated /
--      charge.refund.updated with status failed or canceled). The refund row becomes failed, "received" is cleared on the
--      goal, the admins are alerted (rule 1) and the trainee is told it is being sorted out. (Before: nothing - the app
--      went on showing the refund as sent and received.)
--   3) record_transfer_reversal(): a payout reversed in Stripe (transfer.reversed) is noted on the payout and the admins
--      are alerted.
-- Not handled on purpose: checkout.session.expired. A trainee who restarts a checkout has a second session; releasing
-- the credit reservation when the FIRST one expires would cancel the reservation the second one is using. The 40-minute
-- expiry from GH already returns the credit.
-- All internal: the payment server (service_role) only. Safe to re-run.

create or replace function public._admin_alert(p_title text, p_body text, p_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if to_regclass('public.push_outbox') is null then return; end if;
  insert into public.push_outbox (to_user, kind, title, body, url)
  select p.id, 'offer', left(coalesce(p_title, 'Formtrace'), 120), left(coalesce(p_body, ''), 300), coalesce(p_url, '/#admin')
    from public.profiles p where p.is_admin is true;
exception when others then raise warning '_admin_alert skipped: %', sqlerrm;
end $$;

create or replace function public._alert_payment_failed() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_goal text;
begin
  if new.status = 'failed' and old.status is distinct from 'failed' then
    select goal_title into v_goal from public.engagements where id = new.engagement_id;
    perform public._admin_alert(
      case tg_table_name when 'payment_releases' then 'Payout failed' else 'Refund failed' end,
      public._eur(coalesce(new.amount_cents, 0)) || ' - ' || coalesce(v_goal, 'a goal') || ': ' || left(coalesce(new.error, 'no reason given'), 180),
      '/#admin');
  end if;
  return new;
end $$;
drop trigger if exists alert_release_failed on public.payment_releases;
create trigger alert_release_failed after update of status on public.payment_releases
  for each row execute function public._alert_payment_failed();
drop trigger if exists alert_refund_failed on public.payment_refunds;
create trigger alert_refund_failed after update of status on public.payment_refunds
  for each row execute function public._alert_payment_failed();

create or replace function public.record_refund_failure(p_refund text, p_reason text) returns text
language plpgsql security definer set search_path = public as $$
declare r public.payment_refunds; e record;
begin
  select * into r from public.payment_refunds where stripe_refund_id = p_refund for update;
  if not found then return 'unknown'; end if;
  if r.status = 'failed' then return 'already'; end if;
  update public.payment_refunds
     set status = 'failed', error = left('Stripe reported that this refund failed after it was sent: ' || coalesce(nullif(p_reason, ''), 'no reason given'), 500)
   where id = r.id;                                                   -- the trigger above alerts the admins
  update public.engagements set refund_received_at = null where id = r.engagement_id;   -- the tracker must not say "received"
  select trainee_id, goal_title into e from public.engagements where id = r.engagement_id;
  if found and to_regclass('public.push_outbox') is not null then
    begin
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (e.trainee_id, 'offer', 'Your refund hit a problem',
              'The refund of ' || public._eur(coalesce(r.amount_cents, 0)) || ' for "' || coalesce(e.goal_title, 'your goal')
              || '" did not reach your card. We have been alerted and will sort it out - you do not need to do anything.', '/#notifications');
    exception when others then raise warning 'refund-failure push skipped: %', sqlerrm; end;
  end if;
  return 'failed';
end $$;

create or replace function public.record_transfer_reversal(p_transfer text, p_reversed_cents bigint) returns text
language plpgsql security definer set search_path = public as $$
declare rel public.payment_releases; v_goal text;
begin
  select * into rel from public.payment_releases where stripe_transfer_id = p_transfer for update;
  if not found then return 'unknown'; end if;
  update public.payment_releases
     set error = left('reversed in Stripe: ' || public._eur(coalesce(p_reversed_cents, 0)) || ' of ' || public._eur(coalesce(rel.amount_cents, 0)), 500)
   where id = rel.id;
  select goal_title into v_goal from public.engagements where id = rel.engagement_id;
  perform public._admin_alert('Payout reversed',
    public._eur(coalesce(p_reversed_cents, 0)) || ' of the ' || public._eur(coalesce(rel.amount_cents, 0)) || ' payout for ' || coalesce(v_goal, 'a goal')
    || ' (week of ' || coalesce(rel.week_start::text, '?') || ') was reversed in Stripe.', '/#admin');
  return 'noted';
end $$;

-- internal (the GD rule: name all three roles)
revoke execute on function public._admin_alert(text, text, text)            from public, anon, authenticated;
revoke execute on function public._alert_payment_failed()                   from public, anon, authenticated;
revoke execute on function public.record_refund_failure(text, text)         from public, anon, authenticated;
revoke execute on function public.record_transfer_reversal(text, bigint)    from public, anon, authenticated;
grant  execute on function public.record_refund_failure(text, text)         to service_role;
grant  execute on function public.record_transfer_reversal(text, bigint)    to service_role;

-- Check: expect  functions = 4 | triggers = 2 | open_to_users = 0 | admins >= 1
select (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
          and p.proname in ('_admin_alert','_alert_payment_failed','record_refund_failure','record_transfer_reversal')) as functions,
       (select count(*) from pg_trigger where tgname in ('alert_release_failed','alert_refund_failed') and not tgisinternal) as triggers,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
          and p.proname in ('_admin_alert','_alert_payment_failed','record_refund_failure','record_transfer_reversal')
          and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))) as open_to_users,
       (select count(*) from public.profiles where is_admin is true) as admins;
