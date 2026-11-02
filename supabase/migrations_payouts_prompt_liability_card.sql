-- =====================================================================
-- FormTrace — two pieces:
--  (1) a coach who is approved is pushed straight to setting up Stripe payouts
--      (only while Stripe payments are on - before that the card is hidden anyway);
--  (2) the admin card's liability-review numbers (admins only).
-- =====================================================================

-- (1) approval -> "set up payouts" push. Never blocks the approval.
create or replace function public._payouts_on_approval() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.status = 'approved' and old.status is distinct from 'approved'
       and coalesce((select value from public.platform_rates where key = 'payments_via_stripe'), 0) = 1
       and to_regclass('public.push_outbox') is not null then
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (new.user_id, 'payouts', '✅ You''re approved as a FormTrace coach',
              'Set up payouts with Stripe now so every delivered week reaches your bank - Profile → Get paid with Stripe.', '/#profile');
    end if;
  exception when others then
    raise warning '_payouts_on_approval skipped: %', sqlerrm;
  end;
  return new;
end; $$;
drop trigger if exists payouts_on_approval on public.coach_applications;
create trigger payouts_on_approval after update of status on public.coach_applications
  for each row execute function public._payouts_on_approval();

-- (2) the numbers behind the liability review triggers. Live money only (test-mode
--     deposits are reported separately). Disputes and losses are not tracked yet.
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
    'refunds_quarter_cents', case when to_regclass('public.payment_refunds') is null then 0 else
        coalesce((select sum(rf.amount_cents) from public.payment_refunds rf join public.engagements e on e.id = rf.engagement_id
                   where rf.status = 'sent' and rf.sent_at >= q0 and e.deposit_livemode is true), 0) end,
    'disputes_tracked', false
  ) into r;
  return r;
end; $$;
revoke execute on function public.admin_liability_stats() from public;
grant  execute on function public.admin_liability_stats() to authenticated;   -- the function itself refuses non-admins

select (select count(*) from pg_trigger where tgname = 'payouts_on_approval') as approval_trigger,
       (select count(*) from pg_proc where proname = 'admin_liability_stats') as stats_function;
