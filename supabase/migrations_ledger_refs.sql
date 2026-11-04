-- Item FQ (owner, 2026-11-04): every credit movement and every refund has a unique reference - random, hash-derived,
-- not sequential, so it cannot be guessed: CR-xxxx-xxxx-xxxx-xxxx (credit) and RF-xxxx-xxxx-xxxx-xxxx (refund),
-- 16 hex characters of a SHA-256 of random input (64 bits). Unique across all accounts (unique index). Existing rows get one
-- now; new rows get one automatically (column default), including refunds re-issued after a dispute.
-- Uses Postgres' built-in sha256() - no extension needed. Safe to re-run.

create or replace function public._new_ref(p_prefix text) returns text
language sql volatile as $$
  with h as (select upper(encode(sha256(convert_to(gen_random_uuid()::text || clock_timestamp()::text || random()::text, 'UTF8')), 'hex')) as x)
  select p_prefix || '-' || substr(x, 1, 4) || '-' || substr(x, 5, 4) || '-' || substr(x, 9, 4) || '-' || substr(x, 13, 4) from h
$$;

alter table public.trainee_credits add column if not exists ref text;
update public.trainee_credits set ref = public._new_ref('CR') where ref is null;
alter table public.trainee_credits alter column ref set default public._new_ref('CR');
alter table public.trainee_credits alter column ref set not null;
create unique index if not exists trainee_credits_ref_key on public.trainee_credits (ref);

alter table public.payment_refunds add column if not exists ref text;
update public.payment_refunds set ref = public._new_ref('RF') where ref is null;
alter table public.payment_refunds alter column ref set default public._new_ref('RF');
alter table public.payment_refunds alter column ref set not null;
create unique index if not exists payment_refunds_ref_key on public.payment_refunds (ref);

-- Check: expect  missing = 0 | unique_indexes = 2 | sample like CR-xxxx-xxxx-xxxx-xxxx
select (select count(*) from public.trainee_credits where ref is null) + (select count(*) from public.payment_refunds where ref is null) as missing,
       (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('trainee_credits_ref_key','payment_refunds_ref_key')) as unique_indexes,
       public._new_ref('CR') as sample;