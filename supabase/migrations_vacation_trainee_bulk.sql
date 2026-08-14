-- =====================================================================
-- FormTrace — vacation mode revision: trainee pause becomes whole-account
--
-- Originally item M was per-goal (pause one goal at a time, on My Goals).
-- Revised: a trainee's pause now behaves like the coach's already does —
-- one action, every active goal — and the trigger moves to the bottom of
-- the Training tab. Per-goal pause/resume (start_pause/end_pause) is left
-- in place underneath; these two are the "do it to everything" wrappers,
-- exactly mirroring start_pause_all for coaches.
-- =====================================================================

create or replace function public.start_pause_all_mine(p_message text, p_ends_on date default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n integer := 0;
  eng record;
begin
  if p_ends_on is not null and p_ends_on < current_date then raise exception 'end date must be today or later'; end if;
  for eng in select id from public.engagements where trainee_id = uid and status = 'active' loop
    insert into public.engagement_pauses (engagement_id, triggered_by, message, starts_on, ends_on)
    values (eng.id, uid, p_message, current_date, p_ends_on);
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke execute on function public.start_pause_all_mine(text,date) from public;
grant  execute on function public.start_pause_all_mine(text,date) to authenticated;

create or replace function public.end_pause_all_mine()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  n integer := 0;
  eng record;
  m integer;
begin
  for eng in select id from public.engagements where trainee_id = uid and status = 'active' loop
    update public.engagement_pauses
       set ends_on = current_date - 1
     where engagement_id = eng.id
       and (ends_on is null or ends_on >= current_date);
    get diagnostics m = row_count;
    n := n + m;
  end loop;
  return n;
end;
$$;

revoke execute on function public.end_pause_all_mine() from public;
grant  execute on function public.end_pause_all_mine() to authenticated;

select proname from pg_proc where proname in ('start_pause_all_mine','end_pause_all_mine') order by proname;
