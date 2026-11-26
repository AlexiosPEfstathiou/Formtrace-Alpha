-- IW (owner, 2026-11-26): mute a recorded set before the coach sees it. Like trim (BC) and rotation, an offset-style flag on
-- video_orientation applied at playback - the file is not re-encoded. Only the person who recorded the clip (first path
-- segment = their id) can set it, through a security definer function; there is no column grant, so a coach cannot
-- switch the sound back on.
alter table public.video_orientation add column if not exists muted boolean not null default false;
grant select (muted) on public.video_orientation to authenticated;

create or replace function public.set_my_video_muted(p_path text, p_muted boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_path is null or split_part(p_path,'/',1) <> auth.uid()::text then raise exception 'Not your video'; end if;
  insert into video_orientation(path, muted, updated_by, updated_at) values (p_path, coalesce(p_muted,false), auth.uid(), now())
  on conflict (path) do update set muted = excluded.muted, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
end $$;
revoke execute on function public.set_my_video_muted(text, boolean) from public, anon, authenticated;
grant execute on function public.set_my_video_muted(text, boolean) to authenticated;

select column_name, data_type, column_default from information_schema.columns
 where table_schema='public' and table_name='video_orientation' and column_name='muted';
