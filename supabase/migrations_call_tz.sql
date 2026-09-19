-- CN-2: call proposals carry the proposer's time zone; the app converts for a viewer elsewhere.
alter table public.call_proposals add column if not exists tz text;
create or replace function public.set_call_tz(p_id uuid, p_tz text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.call_proposals set tz = left(p_tz, 64) where id = p_id and proposed_by = auth.uid();
end; $$;
revoke execute on function public.set_call_tz(uuid,text) from public;
grant  execute on function public.set_call_tz(uuid,text) to authenticated;
select 'call tz' as check, count(*) from information_schema.columns where table_schema='public' and table_name='call_proposals' and column_name='tz';
