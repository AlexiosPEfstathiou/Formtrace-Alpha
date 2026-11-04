-- Item EJ part 2 (2026-11-04): 3D Secure on card payments. checkout-create reads three_ds_min_cents:
--   0  (default) = request 3D Secure on every card payment ("any" - the bank may approve without a challenge)
--   N  = only for card payments of N cents or more
--  -1  = leave it to Stripe ("automatic")
-- A dispute for fraud on a 3D Secure-authenticated payment generally shifts the loss to the card issuer.
-- Radar: stay on Radar Lite (free on standard pricing); custom rules need Radar Plus (paid) - not needed for the pilot.
-- Safe to re-run (keeps a value already set).
insert into public.platform_rates (key, value, note) values
  ('three_ds_min_cents', 0, 'EJ: request 3D Secure for card payments of at least this many cents; 0 = all, -1 = Stripe decides')
on conflict (key) do nothing;

-- Check: expect  three_ds_min_cents = 0
select key, value from public.platform_rates where key = 'three_ds_min_cents';