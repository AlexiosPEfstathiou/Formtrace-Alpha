-- =====================================================================
-- FormTrace — make the streak use the user's local date
-- Run in the Supabase SQL editor.
--
-- WHY
--   compute_streak anchored on current_date, which is UTC. The client
--   anchors on the device's local date. In BST that disagrees between
--   midnight and 01:00 — the server still thinks it is yesterday, so the
--   badge can under-report by a day exactly when someone logs late at
--   night. Every timezone ahead of UTC has the same window.
--
-- APPROACH
--   The caller passes its local date. Both functions gain a p_today
--   parameter defaulting to current_date, so anything that cannot know a
--   timezone still works unchanged.
--
--   The old zero/one-argument versions are dropped first: adding a
--   defaulted parameter would otherwise leave two candidates and Postgres
--   would refuse the call as ambiguous.
-- =====================================================================

drop function if exists public.compute_streak(uuid);
drop function if exists public.refresh_my_streak();

-- ---------------------------------------------------------------------
-- core computation, now anchored on a caller-supplied date
-- ---------------------------------------------------------------------
create or replace function public.compute_streak(p_trainee uuid, p_today date default current_date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_today   date := coalesce(p_today, current_date);
  v_anchor  date;
  v_count   integer := 0;
  v_cur     date;
  v_guard   integer := 0;
begin
  foreach v_cur in array array[v_today, v_today - 1, v_today + 1]
  loop
    if public._day_complete(p_trainee, v_cur) then
      v_anchor := v_cur;
      exit;
    end if;
  end loop;

  if v_anchor is null then
    return 0;
  end if;

  v_cur := v_anchor; v_guard := 0;
  while v_guard < 400 and public._day_complete(p_trainee, v_cur) loop
    v_count := v_count + 1;
    v_cur := v_cur - 1;
    v_guard := v_guard + 1;
  end loop;

  v_cur := v_anchor + 1; v_guard := 0;
  while v_guard < 400 and public._day_complete(p_trainee, v_cur) loop
    v_count := v_count + 1;
    v_cur := v_cur + 1;
    v_guard := v_guard + 1;
  end loop;

  return v_count;
end;
$$;

-- ---------------------------------------------------------------------
-- self-refresh RPC. The app passes its device date; omitting it falls
-- back to server time so nothing breaks if an older client calls it.
-- ---------------------------------------------------------------------
create or replace function public.refresh_my_streak(p_today date default current_date)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v integer;
begin
  if auth.uid() is null then
    return 0;
  end if;
  v := public.compute_streak(auth.uid(), coalesce(p_today, current_date));
  update public.profiles set streak_count = v where id = auth.uid();
  return v;
end;
$$;

grant execute on function public.refresh_my_streak(date) to authenticated;
revoke execute on function public.compute_streak(uuid, date) from public;

-- refresh_streak(uuid) is unchanged and still used by the triggers. It has
-- no way to know a device timezone, so trigger-driven refreshes remain on
-- server time; the client's refresh_my_streak call on login and when the
-- calendar opens is what corrects the value for that user.

select proname, pronargs from pg_proc
where proname in ('compute_streak','refresh_my_streak') order by proname;
