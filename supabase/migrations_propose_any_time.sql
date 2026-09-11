-- =====================================================================
-- FormTrace — Item AY (scheduling half): propose any date and time.
-- Run in the Supabase SQL editor. Replaces propose_call() from
-- migrations_scheduled_calls.sql.
--
-- The availability-window rule ("a proposal must fall inside hours BOTH
-- parties declared free") was judged not user friendly. Proposing is now
-- simply: pick a date and a time, send; the other side accepts, declines,
-- or counters - exactly as before. Counters route through this same
-- function (respond_to_call_proposal -> propose_call), so this single
-- change relaxes both. availability_blocks stays in the schema for now,
-- unused by the app; removal is a later cleanup.
-- =====================================================================
create or replace function public.propose_call(
  p_engagement_id uuid, p_date date, p_start_time time, p_end_time time
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

  select id, coach_id, trainee_id, status into v_eng
  from public.engagements where id = p_engagement_id;
  if not found then raise exception 'engagement not found'; end if;
  if v_eng.status <> 'active' then raise exception 'this engagement is not active'; end if;
  if uid <> v_eng.coach_id and uid <> v_eng.trainee_id then raise exception 'not a party to this engagement'; end if;

  -- Only one live thread per engagement: a fresh proposal (opening or counter)
  -- supersedes whatever was pending before it.
  update public.call_proposals set status = 'declined', responded_at = now()
  where engagement_id = p_engagement_id and status = 'pending';

  insert into public.call_proposals (engagement_id, proposed_by, proposed_date, start_time, end_time)
  values (p_engagement_id, uid, p_date, p_start_time, p_end_time)
  returning * into v_row;
  return v_row;
end;
$$;
grant execute on function public.propose_call(uuid, date, time, time) to authenticated;

select 'propose_call relaxed' as check, 1;
