-- =====================================================================
-- FormTrace — Item CE: Web Push. Run in the Supabase SQL editor.
-- Client subscribes (PushManager) and stores the subscription here; the
-- push-send Edge Function reads it (service role) and sends.
-- =====================================================================
create table if not exists public.push_subscriptions (
  endpoint   text primary key,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  p256dh     text not null,
  auth       text not null,
  ua         text,
  created_at timestamptz not null default now(),
  last_ok_at timestamptz,
  fail_count integer not null default 0
);
create index if not exists push_subscriptions_user on public.push_subscriptions(user_id);
alter table public.push_subscriptions enable row level security;
drop policy if exists "own subscriptions" on public.push_subscriptions;
create policy "own subscriptions" on public.push_subscriptions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- the public VAPID key, readable by the app (the private key lives ONLY in the Edge Function secrets)
create table if not exists public.push_config (
  key   text primary key,
  value text not null
);
alter table public.push_config enable row level security;
drop policy if exists "anyone reads push config" on public.push_config;
create policy "anyone reads push config" on public.push_config for select to authenticated using (true);
insert into public.push_config (key, value) values ('vapid_public', 'REPLACE_WITH_YOUR_VAPID_PUBLIC_KEY') on conflict (key) do nothing;

-- per-type opt-outs live on the profile (jsonb; absent = on)
alter table public.profiles add column if not exists push_prefs jsonb not null default '{}'::jsonb;
create or replace function public.set_push_prefs(p_prefs jsonb)
returns void language sql security definer set search_path = public as $$
  update public.profiles set push_prefs = coalesce(p_prefs, '{}'::jsonb) where id = auth.uid();
$$;
revoke execute on function public.set_push_prefs(jsonb) from public;
grant  execute on function public.set_push_prefs(jsonb) to authenticated;

-- outbox: every event that should become a push lands here (by trigger); the Edge
-- Function is called by a Database Webhook on INSERT into this table. One row = one
-- recipient. Keeping the composition in SQL means the copy stays with the data.
create table if not exists public.push_outbox (
  id         bigserial primary key,
  to_user    uuid not null,
  kind       text not null,
  title      text not null,
  body       text not null,
  url        text not null default '/',
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  error      text
);
alter table public.push_outbox enable row level security;   -- no client policies: service role only

create or replace function public._name_of(p uuid) returns text language sql stable security definer set search_path = public as $$
  select coalesce(display_name, 'Someone') from public.profiles where id = p;
$$;

-- ---- triggers that compose pushes ----
create or replace function public.push_on_celebration() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.push_outbox (to_user, kind, title, body, url)
  values (new.to_user, 'clap', '👏 ' || public._name_of(new.from_user) || ' congratulated you',
          case when new.event_kind = 'week' then 'for ' || new.event_text else new.event_text end, '/#notifications');
  return new;
end; $$;
drop trigger if exists push_on_celebration on public.celebrations;
create trigger push_on_celebration after insert on public.celebrations for each row
  when (new.seen_at is null) execute function public.push_on_celebration();

create or replace function public.push_on_handle_share() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.push_outbox (to_user, kind, title, body, url)
  values (new.to_user, 'connect', '🔗 ' || public._name_of(new.from_user) || ' shared their ' || initcap(new.network),
          new.handle, '/#notifications');
  return new;
end; $$;
drop trigger if exists push_on_handle_share on public.handle_shares;
create trigger push_on_handle_share after insert or update of revoked_at on public.handle_shares for each row
  when (new.revoked_at is null) execute function public.push_on_handle_share();

create or replace function public.push_on_connection() returns trigger language plpgsql security definer set search_path = public as $$
declare requester uuid; other uuid;
begin
  if new.status = 'pending' and (tg_op = 'INSERT' or old.status is distinct from 'pending') then
    -- the side that has already confirmed is the requester; notify the other
    requester := case when new.a_ok and not new.b_ok then new.a when new.b_ok and not new.a_ok then new.b else null end;
    if requester is not null then
      other := case when requester = new.a then new.b else new.a end;
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (other, 'knock', '🤝 ' || public._name_of(requester) || ' wants to connect', 'Confirm in Social', '/#intouch');
    end if;
  elsif new.status = 'confirmed' and old.status is distinct from 'confirmed' then
    insert into public.push_outbox (to_user, kind, title, body, url) values (new.a, 'knock', '🤝 You and ' || public._name_of(new.b) || ' are connected', 'You will see each other''s wins', '/#intouch');
    insert into public.push_outbox (to_user, kind, title, body, url) values (new.b, 'knock', '🤝 You and ' || public._name_of(new.a) || ' are connected', 'You will see each other''s wins', '/#intouch');
  end if;
  return new;
end; $$;
drop trigger if exists push_on_connection on public.connections;
create trigger push_on_connection after insert or update on public.connections for each row execute function public.push_on_connection();

create or replace function public.push_on_offer() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (new.trainee_id, 'offer', '✉ New offer from ' || public._name_of(new.coach_id), coalesce(new.title,'Your goal') || ' · ' || coalesce(new.price_text,''), '/#listings');
  elsif tg_op = 'UPDATE' and new.status = 'countered' and old.status is distinct from 'countered' then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (new.coach_id, 'offer', '↩ ' || public._name_of(new.trainee_id) || ' proposed a change', coalesce(new.title,'Offer') || ' · 48 h to respond', '/#market');
  elsif tg_op = 'UPDATE' and new.status = 'pending' and old.status = 'countered' then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (new.trainee_id, 'offer', case when new.counter_outcome='accepted' then '✓ Your change was accepted' else '↩ Original terms kept' end, coalesce(new.title,'Offer') || ' · your decision', '/#listings');
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status is distinct from 'accepted' then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (new.coach_id, 'offer', '🎉 ' || public._name_of(new.trainee_id) || ' accepted your offer', coalesce(new.title,'Goal'), '/#trainee-home');
  end if;
  return new;
end; $$;
drop trigger if exists push_on_offer on public.offers;
create trigger push_on_offer after insert or update on public.offers for each row execute function public.push_on_offer();

create or replace function public.push_on_review() returns trigger language plpgsql security definer set search_path = public as $$
declare t uuid;
begin
  select s.trainee_id into t from public.submissions s where s.id = new.submission_id;
  if t is not null then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (t, 'review', '📝 Your coach reviewed a workout', 'Tags, notes and voice-over are ready', '/#trainee-home');
  end if;
  return new;
end; $$;
drop trigger if exists push_on_review on public.reviews;
create trigger push_on_review after insert on public.reviews for each row execute function public.push_on_review();

create or replace function public.push_on_call() returns trigger language plpgsql security definer set search_path = public as $$
declare e record; other uuid;
begin
  select coach_id, trainee_id into e from public.engagements where id = new.engagement_id;
  if e is null then return new; end if;
  other := case when new.proposed_by = e.coach_id then e.trainee_id else e.coach_id end;
  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (other, 'call', '📞 ' || public._name_of(new.proposed_by) || ' proposed a call', to_char(new.proposed_date,'Dy DD Mon') || ' · ' || left(new.start_time::text,5), '/#trainee-home');
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status is distinct from 'accepted' then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (new.proposed_by, 'call', '📞 Call accepted', to_char(new.proposed_date,'Dy DD Mon') || ' · ' || left(new.start_time::text,5), '/#trainee-home');
  end if;
  return new;
end; $$;
drop trigger if exists push_on_call on public.call_proposals;
create trigger push_on_call after insert or update on public.call_proposals for each row execute function public.push_on_call();

select 'push tables' as check, count(*) from information_schema.tables where table_schema='public' and table_name in ('push_subscriptions','push_config','push_outbox');
