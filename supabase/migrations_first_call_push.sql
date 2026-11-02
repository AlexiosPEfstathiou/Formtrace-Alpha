-- =====================================================================
-- FormTrace — Item EN: when a goal starts, push both people to arrange their first call.
-- "Starts" = accepted (manual route) or deposit paid (Stripe escrow - acceptance alone is
-- not a start while the deposit is unpaid). One push each, once per goal. Kind 'call', so
-- the "Video calls" switch mutes it. Every trigger catches its own errors (CLAUDE.md 7).
-- =====================================================================

-- once-only ledger (no recursion into engagements)
create table if not exists public.push_once (
  key        text primary key,
  created_at timestamptz not null default now()
);
alter table public.push_once enable row level security;   -- no policies: server only

create or replace function public._push_first_call(p_eng uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e record; ins int;
begin
  if to_regclass('public.push_outbox') is null then return; end if;
  insert into public.push_once (key) values ('first_call:' || p_eng) on conflict do nothing;
  get diagnostics ins = row_count;
  if ins = 0 then return; end if;                      -- already pushed for this goal
  select id, coach_id, trainee_id, coalesce(goal_title, 'your goal') as goal into e from public.engagements where id = p_eng;
  if e.id is null then return; end if;
  insert into public.push_outbox (to_user, kind, title, body, url) values
    (e.coach_id,   'call', '📞 You''re on with ' || public._name_of(e.trainee_id),
     'Arrange your first call for "' || e.goal || '" - propose a time in the app.', '/#coach'),
    (e.trainee_id, 'call', '📞 You''re on with ' || public._name_of(e.coach_id),
     'Arrange your first call with your coach - pick a time that suits you both.', '/#listings');
end; $$;
revoke execute on function public._push_first_call(uuid) from public;

-- manual route: the goal starts when it is created active (only while Stripe is off)
create or replace function public._first_call_on_start() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.status = 'active'
       and coalesce((select value from public.platform_rates where key = 'payments_via_stripe'), 0) <> 1 then
      perform public._push_first_call(new.id);
    end if;
  exception when others then
    raise warning '_first_call_on_start skipped: %', sqlerrm;
  end;
  return new;
end; $$;
drop trigger if exists first_call_on_start on public.engagements;
create trigger first_call_on_start after insert on public.engagements
  for each row execute function public._first_call_on_start();

-- escrow: the goal starts when the deposit lands
create or replace function public._first_call_on_deposit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  begin
    if old.deposit_at is null and new.deposit_at is not null and new.status = 'active' then
      perform public._push_first_call(new.id);
    end if;
  exception when others then
    raise warning '_first_call_on_deposit skipped: %', sqlerrm;
  end;
  return new;
end; $$;
drop trigger if exists first_call_on_deposit on public.engagements;
create trigger first_call_on_deposit after update of deposit_at on public.engagements
  for each row execute function public._first_call_on_deposit();

-- existing goals are not pushed retroactively: mark every current goal as done
insert into public.push_once (key) select 'first_call:' || id from public.engagements on conflict do nothing;

select (select count(*) from public.push_once where key like 'first_call:%') as goals_marked,
       (select count(*) from pg_trigger where tgname in ('first_call_on_start','first_call_on_deposit')) as triggers;
