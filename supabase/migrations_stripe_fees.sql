-- =====================================================================
-- FormTrace – Items EA + ED: Stripe cost pass-through rates and the comp/processing columns.
-- Safe to re-run. Run in the Supabase SQL editor.
-- =====================================================================

-- EA: Stripe's Irish pricing, confirmed by the owner on Stripe's pricing page before go-live.
-- checkout-create reads these at every Checkout; set stripe_card_pct = 0 (and the others) to
-- switch the "Payment processing" line off without a deploy. Fixed amounts are in euro.
insert into public.platform_rates (key, value, note) values
  ('stripe_card_pct',        1.9,  'EA: card fee % (premium EEA cards; covers every Irish card)'),
  ('stripe_card_fixed',      0.25, 'EA: card fixed fee per deposit, EUR'),
  ('stripe_payout_pct',      0.25, 'EA: Connect payout % per weekly release'),
  ('stripe_payout_fixed',    0.10, 'EA: Connect payout fixed fee per weekly release, EUR'),
  ('stripe_account_monthly', 2.00, 'EA: Connect Express active-account fee per started month, EUR')
on conflict (key) do nothing;

-- EA: the pass-through part of the deposit, in the smallest currency unit. Releases (DY) and
-- refunds (DZ) work on deposit_amount - deposit_processing. ED: deposit_amount = 0 means comp.
alter table public.engagements
  add column if not exists deposit_processing bigint not null default 0;

-- check: expect stripe_rates = 5, has_processing = 1
select (select count(*) from public.platform_rates where key like 'stripe\_%') as stripe_rates,
       (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = 'engagements' and column_name = 'deposit_processing') as has_processing;
