-- CQ-7: Social tab - "Congratulate all" sends ONE celebration for the week and marks
-- every current win of that person as congratulated, so their number clears.
-- Run in the Supabase SQL editor (after migrations_in_touch*.sql).
create or replace function public.congratulate_all(p_to uuid, p_text text default 'this week''s progress')
returns integer language plpgsql security definer set search_path = public as $$
declare n integer := 0; r record; wk date := date_trunc('week', current_date)::date;
begin
  if not public.are_connected(auth.uid(), p_to) then raise exception 'you are not connected'; end if;
  -- mark each uncongratulated win (PB or completed goal, from this week) as congratulated, silently
  for r in
    select 'pb' as kind, p.id::text as ref from public.personal_bests p where p.trainee_id = p_to and p.achieved_at >= wk
    union all
    select 'goal', e.id::text from public.engagements e where e.trainee_id = p_to and e.status='completed' and e.completed_at >= wk
  loop
    insert into public.celebrations (from_user, to_user, event_kind, event_ref, event_text, seen_at)
    values (auth.uid(), p_to, r.kind, r.ref, '(part of the week''s congratulation)', now())
    on conflict do nothing;
    if found then n := n + 1; end if;
  end loop;
  -- the one visible celebration
  insert into public.celebrations (from_user, to_user, event_kind, event_ref, event_text)
  values (auth.uid(), p_to, 'week', wk::text, left(coalesce(p_text,'this week''s progress'), 120))
  on conflict (from_user, to_user, event_kind, event_ref) do update set created_at = now(), seen_at = null, event_text = excluded.event_text;
  return n;
end; $$;
revoke execute on function public.congratulate_all(uuid,text) from public;
grant  execute on function public.congratulate_all(uuid,text) to authenticated;
select 'congratulate_all' as check;
