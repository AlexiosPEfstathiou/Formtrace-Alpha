-- =====================================================================
-- FormTrace — Item AY (part 2 of scheduling): recurring calls + cancel.
-- Run in the Supabase SQL editor. Requires migrations_propose_any_time.sql.
--
-- A proposal can now be ONE-TIME (recur_every_days null) or RECURRING
-- (every N days, at the same time - "every 7" = weekly, "every 14" =
-- fortnightly). Accepting a recurring proposal accepts the series; the
-- client materialises occurrences (proposed_date + k*N) for display, no
-- row per occurrence. Either party can 'cancel' an accepted call or
-- series. A counter keeps the original's recurrence - a different time,
-- same cadence - unless the counter passes its own.
-- =====================================================================
alter table public.call_proposals
  add column if not exists recur_every_days integer
    check (recur_every_days is null or (recur_every_days between 1 and 90));

alter table public.call_proposals drop constraint if exists call_proposals_status_check;
alter table public.call_proposals add constraint call_proposals_status_check
  check (status in ('pending','accepted','declined','countered','cancelled'));

-- ---------- propose_call: + recurrence ----------
drop function if exists public.propose_call(uuid, date, time, time);
create or replace function public.propose_call(
  p_engagement_id uuid, p_date date, p_start_time time, p_end_time time,
  p_recur_every_days integer default null
)
returns public.call_proposals
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_eng record;
  v_row public.call_proposals;
begin
  if p_end_time <= p_start_time then raise exception 'end time must be after start time'; end if;
  if p_date < current_date then raise exception 'cannot propose a date in the past'; end if;
  if p_recur_every_days is not null and (p_recur_every_days < 1 or p_recur_every_days > 90) then
    raise exception 'recurrence must be between 1 and 90 days';
  end if;

  select id, coach_id, trainee_id, status into v_eng
  from public.engagements where id = p_engagement_id;
  if not found then raise exception 'engagement not found'; end if;
  if v_eng.status <> 'active' then raise exception 'this engagement is not active'; end if;
  if uid <> v_eng.coach_id and uid <> v_eng.trainee_id then raise exception 'not a party to this engagement'; end if;

  -- one live PENDING thread per engagement; an accepted series is untouched
  update public.call_proposals set status = 'declined', responded_at = now()
  where engagement_id = p_engagement_id and status = 'pending';

  insert into public.call_proposals (engagement_id, proposed_by, proposed_date, start_time, end_time, recur_every_days)
  values (p_engagement_id, uid, p_date, p_start_time, p_end_time, p_recur_every_days)
  returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function public.propose_call(uuid, date, time, time, integer) from public;
grant  execute on function public.propose_call(uuid, date, time, time, integer) to authenticated;

-- ---------- respond: + cancel, counter keeps recurrence ----------
drop function if exists public.respond_to_call_proposal(uuid, text, date, time, time);
create or replace function public.respond_to_call_proposal(
  p_proposal_id uuid, p_action text,
  p_counter_date date default null, p_counter_start time default null, p_counter_end time default null,
  p_counter_recur integer default null
)
returns public.call_proposals
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_prop record;
  v_eng record;
  v_new public.call_proposals;
begin
  if p_action not in ('accept','decline','counter','cancel') then raise exception 'invalid action'; end if;

  select * into v_prop from public.call_proposals where id = p_proposal_id;
  if not found then raise exception 'proposal not found'; end if;
  select id, coach_id, trainee_id into v_eng from public.engagements where id = v_prop.engagement_id;
  if uid <> v_eng.coach_id and uid <> v_eng.trainee_id then raise exception 'not a party to this engagement'; end if;

  if p_action = 'cancel' then
    -- either party may cancel an accepted call/series, or withdraw their own pending proposal
    if v_prop.status not in ('accepted','pending') then raise exception 'nothing to cancel'; end if;
    if v_prop.status = 'pending' and v_prop.proposed_by <> uid then raise exception 'decline it instead'; end if;
    update public.call_proposals set status = 'cancelled', responded_at = now() where id = p_proposal_id;
    select * into v_new from public.call_proposals where id = p_proposal_id;
    return v_new;
  end if;

  if v_prop.status <> 'pending' then raise exception 'this proposal is no longer pending'; end if;
  if v_prop.expires_at < now() then raise exception 'this proposal has expired'; end if;
  if v_prop.proposed_by = uid then raise exception 'you cannot respond to your own proposal'; end if;

  if p_action = 'accept' then
    update public.call_proposals set status = 'accepted', responded_at = now() where id = p_proposal_id;
  elsif p_action = 'decline' then
    update public.call_proposals set status = 'declined', responded_at = now() where id = p_proposal_id;
  else
    if p_counter_date is null or p_counter_start is null or p_counter_end is null then
      raise exception 'a counter needs a date, start time, and end time';
    end if;
    update public.call_proposals set status = 'countered', responded_at = now() where id = p_proposal_id;
    v_new := public.propose_call(v_prop.engagement_id, p_counter_date, p_counter_start, p_counter_end,
                                 coalesce(p_counter_recur, v_prop.recur_every_days));
    update public.call_proposals set parent_proposal_id = p_proposal_id where id = v_new.id;
    return v_new;
  end if;

  select * into v_new from public.call_proposals where id = p_proposal_id;
  return v_new;
end;
$$;
revoke execute on function public.respond_to_call_proposal(uuid, text, date, time, time, integer) from public;
grant  execute on function public.respond_to_call_proposal(uuid, text, date, time, time, integer) to authenticated;

select 'recurring calls ready' as check, count(*) from public.call_proposals;
