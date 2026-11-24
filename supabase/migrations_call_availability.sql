-- IK (owner, 2026-11-24): weekly availability returns as SUGGESTIONS, not a rule.
-- Each person keeps their free hours per weekday (availability_blocks, 0 = Sunday as JS getDay());
-- times both share are offered as "Propose" chips; proposing any other time still works
-- (migrations_propose_any_time.sql is unchanged). Writes go through set_my_availability
-- (replace-all, validated); direct table writes are revoked. tz = the person's time zone,
-- so the other side's hours can be converted.
alter table public.availability_blocks add column if not exists tz text;

revoke insert, update, delete, truncate, references, trigger on public.availability_blocks from public, anon, authenticated;
revoke all on public.availability_blocks from anon;
grant select on public.availability_blocks to authenticated;

create or replace function public.set_my_availability(p_blocks jsonb, p_tz text)
returns int language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); b jsonb; n int := 0;
begin
  if me is null then raise exception 'Not signed in'; end if;
  if jsonb_typeof(coalesce(p_blocks,'[]'::jsonb)) <> 'array' then raise exception 'Blocks must be a list'; end if;
  if jsonb_array_length(coalesce(p_blocks,'[]'::jsonb)) > 42 then raise exception 'Too many time ranges'; end if;
  if p_tz is not null and (length(p_tz) > 64 or not exists (select 1 from pg_timezone_names where name = p_tz)) then p_tz := null; end if;
  delete from availability_blocks where user_id = me;
  for b in select * from jsonb_array_elements(coalesce(p_blocks,'[]'::jsonb)) loop
    if (b->>'d')::int not between 0 and 6 or (b->>'e')::time <= (b->>'s')::time then raise exception 'Invalid time range'; end if;
    insert into availability_blocks(user_id, day_of_week, start_time, end_time, tz)
      values (me, (b->>'d')::int, (b->>'s')::time, (b->>'e')::time, p_tz);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke execute on function public.set_my_availability(jsonb, text) from public, anon, authenticated;
grant execute on function public.set_my_availability(jsonb, text) to authenticated;

select (select count(*) from information_schema.columns where table_name='availability_blocks' and column_name='tz') as tz_col,
       has_function_privilege('authenticated','public.set_my_availability(jsonb,text)','execute') as callable,
       has_table_privilege('authenticated','public.availability_blocks','insert') as direct_insert;
