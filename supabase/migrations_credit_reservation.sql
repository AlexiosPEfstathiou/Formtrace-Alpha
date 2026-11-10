-- Item GH (security review 2026-11-10): credit is reserved and spent in one locked step.
-- Before: checkout read the credit balance and spent it in separate steps (and, for part credit, only when the payment
-- landed), so two payments started at the same moment could both use the same credit.
-- Now:
--   pay_goal_with_credit()  full credit: one transaction locks the trainee's credit, re-checks the balance, marks the goal
--                           paid and writes the ledger line - or changes nothing.
--   reserve_credit()        part credit: when a checkout starts, the credit is set aside as a ledger line with an expiry
--                           (reserved_until). Another checkout sees the reduced balance at once.
--   confirm_credit()        when the payment lands, the reservation becomes final.
--   release_credit_reservation() / release_stale_credit_reservations()
--                           an abandoned checkout gives the credit back: at once if Stripe refused the session, otherwise
--                           when the reservation expires (credit checkouts expire after 31 minutes; reservations after 40).
-- All five are internal: callable by the payment server (service_role) only. Safe to re-run.

alter table public.trainee_credits add column if not exists reserved_until timestamptz;
comment on column public.trainee_credits.reserved_until is
  'GH: set while a checkout that uses this credit is open (the line is a reservation); null = a final ledger line.';
create index if not exists trainee_credits_reserved_idx on public.trainee_credits (reserved_until) where reserved_until is not null;

-- expired reservations: give the credit back (goal still unpaid) or make the line final (goal paid, confirmation missed)
create or replace function public._release_stale_credit(p_trainee uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  update public.trainee_credits c set reserved_until = null, note = 'credit used for this goal'
   where c.reserved_until is not null and (p_trainee is null or c.trainee_id = p_trainee)
     and exists (select 1 from public.engagements e where e.id = c.used_engagement and e.deposit_at is not null);
  delete from public.trainee_credits c
   where c.reserved_until is not null and c.reserved_until < now() and (p_trainee is null or c.trainee_id = p_trainee);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.release_stale_credit_reservations() returns integer
language sql security definer set search_path = public as $$ select public._release_stale_credit(null) $$;

create or replace function public.reserve_credit(p_engagement uuid, p_max_cents bigint, p_currency text) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_tr uuid; v_bal bigint; v_take bigint;
begin
  select trainee_id into v_tr from public.engagements where id = p_engagement and deposit_at is null;
  if not found then return 0; end if;
  perform pg_advisory_xact_lock(hashtextextended('ft-credit:' || v_tr::text, 0));     -- one credit operation per trainee at a time
  delete from public.trainee_credits where trainee_id = v_tr and reserved_until is not null and used_engagement = p_engagement;   -- an earlier attempt for this goal
  perform public._release_stale_credit(v_tr);
  select coalesce(sum(amount_cents), 0) into v_bal from public.trainee_credits where trainee_id = v_tr and currency = p_currency;
  v_take := greatest(0, least(coalesce(p_max_cents, 0), v_bal));
  if v_take > 0 then
    insert into public.trainee_credits (trainee_id, amount_cents, currency, used_engagement, note, reserved_until)
    values (v_tr, -v_take, p_currency, p_engagement, 'credit reserved while you pay for this goal - it returns if the payment is not completed', now() + interval '40 minutes');
  end if;
  return v_take;
end $$;

create or replace function public.release_credit_reservation(p_engagement uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.trainee_credits c
   where c.reserved_until is not null and c.used_engagement = p_engagement
     and not exists (select 1 from public.engagements e where e.id = p_engagement and e.deposit_at is not null);
end $$;

create or replace function public.confirm_credit(p_engagement uuid, p_cents bigint, p_currency text) returns void
language plpgsql security definer set search_path = public as $$
declare v_tr uuid; v_id uuid;
begin
  if coalesce(p_cents, 0) <= 0 then return; end if;
  select trainee_id into v_tr from public.engagements where id = p_engagement;
  if not found then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('ft-credit:' || v_tr::text, 0));
  select id into v_id from public.trainee_credits
   where used_engagement = p_engagement and reserved_until is not null order by created_at desc limit 1;
  if found then
    update public.trainee_credits set reserved_until = null, amount_cents = -p_cents, note = 'credit used for this goal' where id = v_id;
    delete from public.trainee_credits where used_engagement = p_engagement and reserved_until is not null;     -- any older duplicate
  elsif not exists (select 1 from public.trainee_credits where used_engagement = p_engagement and amount_cents < 0) then
    -- a checkout started before reservations existed (or whose reservation had expired): record the use now
    insert into public.trainee_credits (trainee_id, amount_cents, currency, used_engagement, note)
    values (v_tr, -p_cents, p_currency, p_engagement, 'credit used for this goal');
  end if;
end $$;

create or replace function public.pay_goal_with_credit(p_engagement uuid, p_need bigint, p_processing bigint, p_currency text, p_livemode boolean) returns text
language plpgsql security definer set search_path = public as $$
declare e public.engagements; v_bal bigint;
begin
  select * into e from public.engagements where id = p_engagement for update;
  if not found then return 'not_found'; end if;
  if e.deposit_at is not null then return 'already_paid'; end if;
  perform pg_advisory_xact_lock(hashtextextended('ft-credit:' || e.trainee_id::text, 0));
  delete from public.trainee_credits where trainee_id = e.trainee_id and reserved_until is not null and used_engagement = p_engagement;
  perform public._release_stale_credit(e.trainee_id);
  select coalesce(sum(amount_cents), 0) into v_bal from public.trainee_credits where trainee_id = e.trainee_id and currency = p_currency;
  if coalesce(p_need, 0) <= 0 or v_bal < p_need then return 'insufficient'; end if;
  update public.engagements
     set deposit_at = now(), deposit_amount = 0, deposit_processing = coalesce(p_processing, 0), deposit_credit_cents = p_need,
         deposit_currency = p_currency, deposit_livemode = p_livemode
   where id = p_engagement;
  insert into public.trainee_credits (trainee_id, amount_cents, currency, used_engagement, note)
  values (e.trainee_id, -p_need, p_currency, p_engagement, 'credit used for this goal (paid in full)');
  return 'paid';
end $$;

-- internal: the payment server only (rule from GD: name all three roles)
revoke execute on function public._release_stale_credit(uuid)                               from public, anon, authenticated;
revoke execute on function public.release_stale_credit_reservations()                       from public, anon, authenticated;
revoke execute on function public.reserve_credit(uuid, bigint, text)                        from public, anon, authenticated;
revoke execute on function public.release_credit_reservation(uuid)                          from public, anon, authenticated;
revoke execute on function public.confirm_credit(uuid, bigint, text)                        from public, anon, authenticated;
revoke execute on function public.pay_goal_with_credit(uuid, bigint, bigint, text, boolean) from public, anon, authenticated;
grant  execute on function public.reserve_credit(uuid, bigint, text)                        to service_role;
grant  execute on function public.release_credit_reservation(uuid)                          to service_role;
grant  execute on function public.confirm_credit(uuid, bigint, text)                        to service_role;
grant  execute on function public.pay_goal_with_credit(uuid, bigint, bigint, text, boolean) to service_role;

-- every 10 minutes: return expired reservations
do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'formtrace-credit-reservations';
    perform cron.schedule('formtrace-credit-reservations', '*/10 * * * *', 'select public.release_stale_credit_reservations()');
  end if;
end $$;

-- Check: expect  column_ok = 1 | functions = 6 | open_to_users = 0 | cron_job = 1
select (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'trainee_credits' and column_name = 'reserved_until') as column_ok,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
          and p.proname in ('_release_stale_credit','release_stale_credit_reservations','reserve_credit','release_credit_reservation','confirm_credit','pay_goal_with_credit')) as functions,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
          and p.proname in ('_release_stale_credit','release_stale_credit_reservations','reserve_credit','release_credit_reservation','confirm_credit','pay_goal_with_credit')
          and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))) as open_to_users,
       (select count(*) from cron.job where jobname = 'formtrace-credit-reservations') as cron_job;
