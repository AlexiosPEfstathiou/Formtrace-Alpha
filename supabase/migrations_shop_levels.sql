-- HI (owner, 2026-11-20): levels and the points shop.
-- Levels need no table: exp = every point ever earned (positive points_ledger rows) - spending points never lowers it.
-- The shop: shop_items (the catalogue, read-only to users, empty until the owner stocks it), shop_purchases (each user
-- sees their own) and buy_shop_item(), which checks the balance and records the purchase and the negative points row
-- together. Users write nothing directly. Safe to re-run.

create table if not exists public.shop_items (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  description  text,
  icon         text,                       -- an emoji for now (openart art later - DESIGN_ASSETS)
  price_points integer not null check (price_points > 0),
  active       boolean not null default true,
  sort         integer not null default 0,
  created_at   timestamptz not null default now()
);
alter table public.shop_items enable row level security;
drop policy if exists "shop items readable" on public.shop_items;
create policy "shop items readable" on public.shop_items for select to authenticated using (active);
revoke all on public.shop_items from anon, authenticated;
grant select on public.shop_items to authenticated;

create table if not exists public.shop_purchases (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  item_id      uuid not null references public.shop_items(id),
  price_points integer not null,
  created_at   timestamptz not null default now()
);
create index if not exists shop_purchases_user_idx on public.shop_purchases (user_id, created_at desc);
alter table public.shop_purchases enable row level security;
drop policy if exists "own purchases" on public.shop_purchases;
create policy "own purchases" on public.shop_purchases for select using (user_id = auth.uid());
revoke all on public.shop_purchases from anon, authenticated;
grant select on public.shop_purchases to authenticated;

create or replace function public.buy_shop_item(p_item uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); it public.shop_items; v_bal bigint; v_pid uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into it from public.shop_items where id = p_item and active;
  if not found then raise exception 'This item is not in the shop'; end if;
  perform pg_advisory_xact_lock(hashtext('points:' || uid));   -- one purchase at a time per person
  select coalesce(sum(amount), 0) into v_bal from public.points_ledger where user_id = uid;
  if v_bal < it.price_points then raise exception 'Not enough points'; end if;
  insert into public.shop_purchases (user_id, item_id, price_points) values (uid, it.id, it.price_points) returning id into v_pid;
  insert into public.points_ledger (user_id, amount, reason, ref)
  values (uid, -it.price_points, 'Shop: ' || it.name, 'shop:' || v_pid);
  return jsonb_build_object('purchase', v_pid, 'balance', v_bal - it.price_points);
end $$;
revoke execute on function public.buy_shop_item(uuid) from public, anon, authenticated;
grant  execute on function public.buy_shop_item(uuid) to authenticated;

-- Check: expect  tables 2 | rls 2 | buy_callable true
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('shop_items', 'shop_purchases')) as tables,
  (select count(*) from pg_class where relname in ('shop_items', 'shop_purchases') and relrowsecurity) as rls,
  has_function_privilege('authenticated', 'public.buy_shop_item(uuid)', 'execute') as buy_callable;
