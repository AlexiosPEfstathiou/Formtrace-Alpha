-- =====================================================================
-- FormTrace — Item DM: Stripe Checkout deposit on the goal (sandbox first).
-- Written only by the stripe-webhook Edge Function (service role); a trigger refuses
-- any other writer, so no client can mark its own deposit as paid.
-- =====================================================================
alter table public.engagements
  add column if not exists deposit_at              timestamptz,
  add column if not exists deposit_amount          bigint,     -- Stripe amount_total, smallest currency unit
  add column if not exists deposit_currency        text,
  add column if not exists deposit_livemode        boolean,    -- false = Stripe test mode
  add column if not exists stripe_checkout_session text,
  add column if not exists stripe_payment_intent   text;

create or replace function public._guard_deposit_columns() returns trigger language plpgsql as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' and (
       new.deposit_at       is distinct from old.deposit_at
    or new.deposit_amount   is distinct from old.deposit_amount
    or new.deposit_currency is distinct from old.deposit_currency
    or new.deposit_livemode is distinct from old.deposit_livemode
    or new.stripe_checkout_session is distinct from old.stripe_checkout_session
    or new.stripe_payment_intent   is distinct from old.stripe_payment_intent) then
    raise exception 'deposit fields are written by the payment server only';
  end if;
  return new;
end; $$;
drop trigger if exists guard_deposit_columns on public.engagements;
create trigger guard_deposit_columns before update on public.engagements
  for each row execute function public._guard_deposit_columns();

select count(*) as deposit_columns from information_schema.columns
 where table_schema='public' and table_name='engagements'
   and column_name in ('deposit_at','deposit_amount','deposit_currency','deposit_livemode','stripe_checkout_session','stripe_payment_intent');
