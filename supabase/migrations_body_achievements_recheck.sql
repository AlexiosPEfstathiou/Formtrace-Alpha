-- =====================================================================
-- FormTrace — DT: a typo (1600 kg) earned "Bulk up", and correcting it left the
-- achievement in place. Body achievements (Bulk up, Weight cut) depend on data that can be
-- corrected, so they are now RE-CHECKED whenever weight data changes and removed if the
-- data no longer supports them. New weights outside 20-400 kg are refused.
-- =====================================================================

-- 1. plausible weights only (new and changed rows; NOT VALID leaves history alone)
alter table public.logs drop constraint if exists logs_weight_plausible;
alter table public.logs add constraint logs_weight_plausible
  check (weight_kg is null or weight_kg between 20 and 400) not valid;

-- 2. re-check the body achievements for one trainee: remove what the data no longer
--    supports, award what it now does
create or replace function public.recheck_body_achievements(p_user uuid)
returns integer language plpgsql security definer set search_path = public as $$
declare cut boolean; bulk boolean; n int := 0;
begin
  select coalesce(bool_or(last_w <= first_w * 0.95), false), coalesce(bool_or(last_w >= first_w * 1.05), false)
    into cut, bulk
    from (
      select (select l.weight_kg from public.logs l where l.trainee_id = p_user and l.weight_kg is not null
                and l.log_date >= (e.started_at at time zone 'UTC')::date order by l.log_date asc  limit 1) as first_w,
             (select l.weight_kg from public.logs l where l.trainee_id = p_user and l.weight_kg is not null
                and l.log_date >= (e.started_at at time zone 'UTC')::date order by l.log_date desc limit 1) as last_w
        from public.engagements e where e.trainee_id = p_user
    ) x where first_w is not null and last_w is not null;
  delete from public.user_achievements
   where user_id = p_user and ((code = 'cutting' and not cut) or (code = 'bulking' and not bulk));
  get diagnostics n = row_count;
  perform public.check_achievements(p_user);   -- awards them if the corrected data now justifies it
  return n;                                     -- how many were removed
end; $$;
revoke execute on function public.recheck_body_achievements(uuid) from public;

-- 3. run it whenever weight data changes (never blocks the save)
create or replace function public._ach_on_weight() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    perform public.recheck_body_achievements(case when tg_op = 'DELETE' then old.trainee_id else new.trainee_id end);
  exception when others then
    raise warning '_ach_on_weight skipped: %', sqlerrm;
  end;
  return null;   -- AFTER trigger: the return value is ignored
end; $$;
drop trigger if exists ach_on_weight on public.logs;
create trigger ach_on_weight after insert or update of weight_kg or delete on public.logs
  for each row execute function public._ach_on_weight();

-- 4. one-time: re-check everyone who holds a body achievement today (fixes the 1600 kg case)
select p.display_name, ua.code, public.recheck_body_achievements(ua.user_id) as removed
  from public.user_achievements ua join public.profiles p on p.id = ua.user_id
 where ua.code in ('cutting','bulking');
