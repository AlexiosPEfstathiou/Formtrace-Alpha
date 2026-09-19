-- =====================================================================
-- FormTrace — CN-12: knock matching fix. Run in the Supabase SQL editor.
-- The polling phone (the one whose knock arrived first) looked only at its
-- knocks WHERE matched IS NULL - but the match had just filled that field,
-- so it was told "no match" and never saw the confirmation. Now the poll
-- reads the latest knock regardless and returns the connection if set.
-- =====================================================================
create or replace function public.register_knock(p_lat double precision, p_lng double precision, p_magnitude double precision, p_poll_only boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  me public.knocks; other public.knocks; c public.connections; o record;
begin
  if uid is null then raise exception 'not signed in'; end if;
  if not p_poll_only then
    insert into public.knocks (user_id, lat, lng, magnitude) values (uid, p_lat, p_lng, p_magnitude) returning * into me;
  else
    select * into me from public.knocks where user_id = uid order by received_at desc limit 1;
    if me.id is null then return jsonb_build_object('matched', false); end if;
    if me.received_at < now() - interval '10 seconds' then return jsonb_build_object('matched', false, 'expired', true); end if;
  end if;
  if me.matched is not null then
    select * into c from public.connections where id = me.matched;
  else
    select k.* into other from public.knocks k
     where k.user_id <> uid and k.matched is null
       and abs(extract(epoch from (k.received_at - me.received_at))) <= 0.8
       and (me.lat is null or k.lat is null or
            (abs(k.lat - me.lat) < 0.0006 and abs(k.lng - me.lng) < 0.0009))
     order by abs(extract(epoch from (k.received_at - me.received_at))) limit 1;
    if other.id is null then return jsonb_build_object('matched', false); end if;
    c := public._connection_for(uid, other.user_id, 'knock');
    update public.knocks set matched = c.id where id in (me.id, other.id);
  end if;
  select p.id, p.display_name, p.avatar_path, p.avatar_initials into o from public.profiles p
   where p.id = case when c.a = uid then c.b else c.a end;
  return jsonb_build_object('matched', true, 'connection_id', c.id, 'status', c.status,
    'other', jsonb_build_object('id', o.id, 'display_name', o.display_name, 'avatar_path', o.avatar_path, 'avatar_initials', o.avatar_initials));
end; $$;

select 'register_knock updated' as check;
