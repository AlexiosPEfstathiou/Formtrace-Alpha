-- IO (owner, 2026-11-25): Formtrace events on the Social tab (e.g. "Formtrace meetup, Marina Walk,
-- Sunday 10:00 - knock to make friends, coffee, feedback with the dev team, limited edition swag").
-- Events are written by the owner in the Supabase table editor (no client writes). Members read
-- active, upcoming events and RSVP through set_event_rsvp; counts come from event_summary (a
-- member sees the total and which of HIS FRIENDS are going - never a list of strangers).
create table if not exists public.formtrace_events(
  id uuid primary key default gen_random_uuid(),
  title text not null,
  place text not null,
  starts_at timestamptz not null,
  perks text,
  maps_query text,
  active boolean not null default false,
  created_at timestamptz not null default now());
create table if not exists public.event_rsvps(
  event_id uuid not null references public.formtrace_events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(event_id,user_id));
alter table public.formtrace_events enable row level security;
alter table public.event_rsvps enable row level security;
drop policy if exists "read active events" on public.formtrace_events;
create policy "read active events" on public.formtrace_events for select to authenticated using (active);
drop policy if exists "read own rsvps" on public.event_rsvps;
create policy "read own rsvps" on public.event_rsvps for select to authenticated using (user_id = auth.uid());
revoke all on public.formtrace_events from public, anon, authenticated;
revoke all on public.event_rsvps from public, anon, authenticated;
grant select on public.formtrace_events to authenticated;
grant select on public.event_rsvps to authenticated;

create or replace function public.set_event_rsvp(p_event uuid, p_going boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if not exists (select 1 from formtrace_events where id = p_event and active and starts_at > now() - interval '3 hours') then raise exception 'This event is not open'; end if;
  if p_going then insert into event_rsvps(event_id,user_id) values (p_event, auth.uid()) on conflict do nothing;
  else delete from event_rsvps where event_id = p_event and user_id = auth.uid(); end if;
end $$;

create or replace function public.event_summary(p_event uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'going', (select count(*) from event_rsvps where event_id = p_event),
    'me', exists (select 1 from event_rsvps where event_id = p_event and user_id = auth.uid()),
    'friends', coalesce((select jsonb_agg(r.user_id) from event_rsvps r
       where r.event_id = p_event and r.user_id <> auth.uid() and exists (select 1 from connections c where c.status='confirmed'
         and ((c.a = auth.uid() and c.b = r.user_id) or (c.b = auth.uid() and c.a = r.user_id)))), '[]'::jsonb))
  where exists (select 1 from formtrace_events where id = p_event and active);
$$;
revoke execute on function public.set_event_rsvp(uuid, boolean) from public, anon, authenticated;
revoke execute on function public.event_summary(uuid) from public, anon, authenticated;
grant execute on function public.set_event_rsvp(uuid, boolean) to authenticated;
grant execute on function public.event_summary(uuid) to authenticated;

-- The example event, OFF until the owner switches it on (active = true) in the table editor.
insert into public.formtrace_events(title, place, starts_at, perks, maps_query, active)
select 'Formtrace meetup', 'Marina Walk', timestamptz '2026-11-29 10:00 Europe/Dublin',
       'Knock, make friends, coffee on us, tell the dev team what to build, limited edition swag', 'Marina Walk, Cork', false
where not exists (select 1 from public.formtrace_events where title = 'Formtrace meetup' and place = 'Marina Walk');

select (select count(*) from public.formtrace_events) as events,
       has_function_privilege('authenticated','public.set_event_rsvp(uuid,boolean)','execute') as rsvp_ok,
       has_table_privilege('authenticated','public.event_rsvps','insert') as direct_insert;
