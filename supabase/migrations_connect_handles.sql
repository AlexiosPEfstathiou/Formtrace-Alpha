-- =====================================================================
-- FormTrace — Item CT "Connect": share your WhatsApp / Instagram / Snapchat
-- handle with a friend (In Touch connection). Run in the Supabase SQL editor.
-- =====================================================================
alter table public.profiles
  add column if not exists whatsapp  text,
  add column if not exists instagram text,
  add column if not exists snapchat  text;
-- profiles has column-level update grants (migrations_coach_profiles.sql revoked table-wide update) - every new column the app writes needs its own grant
grant update (whatsapp, instagram, snapchat) on public.profiles to authenticated;

create table if not exists public.handle_shares (
  id         uuid primary key default gen_random_uuid(),
  from_user  uuid not null references public.profiles(id) on delete cascade,
  to_user    uuid not null references public.profiles(id) on delete cascade,
  network    text not null check (network in ('whatsapp','instagram','snapchat')),
  handle     text not null,                 -- snapshot at share time
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  seen_at    timestamptz,
  unique (from_user, to_user, network)
);
alter table public.handle_shares enable row level security;
drop policy if exists "parties read handle shares" on public.handle_shares;
create policy "parties read handle shares" on public.handle_shares for select to authenticated using (from_user = auth.uid() or to_user = auth.uid());
drop policy if exists "receiver marks seen" on public.handle_shares;
create policy "receiver marks seen" on public.handle_shares for update to authenticated using (to_user = auth.uid()) with check (to_user = auth.uid());

-- share (friends only; handle must be set); re-sharing after a revoke reactivates
create or replace function public.share_handle(p_to uuid, p_network text)
returns public.handle_shares language plpgsql security definer set search_path = public as $$
declare v text; r public.handle_shares;
begin
  if not public.are_connected(auth.uid(), p_to) then raise exception 'you are not connected'; end if;
  select case p_network when 'whatsapp' then whatsapp when 'instagram' then instagram when 'snapchat' then snapchat end
    into v from public.profiles where id = auth.uid();
  if v is null or trim(v) = '' then raise exception 'add your % in Settings first', p_network; end if;
  insert into public.handle_shares (from_user, to_user, network, handle) values (auth.uid(), p_to, p_network, trim(v))
  on conflict (from_user, to_user, network) do update set handle = excluded.handle, created_at = now(), revoked_at = null, seen_at = null
  returning * into r;
  return r;
end; $$;
revoke execute on function public.share_handle(uuid,text) from public;
grant  execute on function public.share_handle(uuid,text) to authenticated;

create or replace function public.revoke_handle(p_to uuid, p_network text)
returns void language sql security definer set search_path = public as $$
  update public.handle_shares set revoked_at = now() where from_user = auth.uid() and to_user = p_to and network = p_network and revoked_at is null;
$$;
revoke execute on function public.revoke_handle(uuid,text) from public;
grant  execute on function public.revoke_handle(uuid,text) to authenticated;

-- disconnecting revokes both ways
create or replace function public.confirm_connection(p_id uuid, p_accept boolean)
returns public.connections language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c public.connections;
begin
  select * into c from public.connections where id = p_id;
  if not found or (c.a <> uid and c.b <> uid) then raise exception 'not your connection'; end if;
  if not p_accept then
    update public.connections set status='ended' where id = p_id returning * into c;
    update public.handle_shares set revoked_at = coalesce(revoked_at, now())
     where (from_user = c.a and to_user = c.b) or (from_user = c.b and to_user = c.a);
    return c;
  end if;
  update public.connections
     set a_ok = case when a = uid then true else a_ok end,
         b_ok = case when b = uid then true else b_ok end
   where id = p_id returning * into c;
  if c.a_ok and c.b_ok and c.status <> 'confirmed' then
    update public.connections set status='confirmed', confirmed_at=now() where id = p_id returning * into c;
  end if;
  return c;
end; $$;


-- Handle saves go through a security-definer function: the direct update was refused with
-- "permission denied for table profiles" on the test phone even with column grants in place.
create or replace function public.set_my_handles(p_whatsapp text, p_instagram text, p_snapchat text)
returns void language sql security definer set search_path = public as $$
  update public.profiles
     set whatsapp  = nullif(trim(coalesce(p_whatsapp,  whatsapp)),  ''),
         instagram = nullif(trim(coalesce(p_instagram, instagram)), ''),
         snapchat  = nullif(trim(coalesce(p_snapchat,  snapchat)),  '')
   where id = auth.uid();
$$;
revoke execute on function public.set_my_handles(text,text,text) from public;
grant  execute on function public.set_my_handles(text,text,text) to authenticated;
select 'connect' as check, count(*) from information_schema.tables where table_schema='public' and table_name='handle_shares';
