-- =====================================================================
-- FormTrace — CN-10: a trainee ends a goal early - "Goal achieved" or "Cancel goal",
-- with a reason. Run in the Supabase SQL editor.
-- =====================================================================
alter table public.engagements
  add column if not exists ended_by   uuid references public.profiles(id),
  add column if not exists end_kind   text check (end_kind is null or end_kind in ('achieved','cancelled')),
  add column if not exists end_reason text,
  add column if not exists end_note   text,
  add column if not exists end_ack_at timestamptz;

create or replace function public.end_goal_early(p_eng uuid, p_kind text, p_reason text, p_note text default null)
returns public.engagements language plpgsql security definer set search_path = public as $$
declare e public.engagements; n integer;
begin
  select * into e from public.engagements where id = p_eng;
  if not found then raise exception 'goal not found'; end if;
  if e.trainee_id <> auth.uid() then raise exception 'only the trainee can end their goal'; end if;
  if e.status <> 'active' then raise exception 'this goal is not active'; end if;
  if p_kind not in ('achieved','cancelled') then raise exception 'kind must be achieved or cancelled'; end if;
  update public.engagements
     set status = case when p_kind = 'achieved' then 'completed' else 'ended' end,
         completed_at = now(),
         ended_by = auth.uid(), end_kind = p_kind,
         end_reason = left(coalesce(p_reason,''), 60), end_note = nullif(left(coalesce(p_note,''), 500), '')
   where id = p_eng returning * into e;
  -- sessions never started disappear from every calendar
  delete from public.assigned_workouts where engagement_id = p_eng and status = 'assigned';
  get diagnostics n = row_count;
  -- tell the coach (push, when CE is switched on)
  if to_regclass('public.push_outbox') is not null then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (e.coach_id, 'offer',
            case when p_kind='achieved' then '🎯 ' || public._name_of(e.trainee_id) || ' marked the goal achieved' else '⏹ ' || public._name_of(e.trainee_id) || ' ended the goal' end,
            coalesce(e.goal_title,'Goal') || ' · ' || coalesce(p_reason,''), '/#trainee-home');
  end if;
  return e;
end; $$;
revoke execute on function public.end_goal_early(uuid,text,text,text) from public;
grant  execute on function public.end_goal_early(uuid,text,text,text) to authenticated;

-- coach acknowledges the card
create or replace function public.ack_goal_end(p_eng uuid)
returns void language sql security definer set search_path = public as $$
  update public.engagements set end_ack_at = now() where id = p_eng and coach_id = auth.uid();
$$;
revoke execute on function public.ack_goal_end(uuid) from public;
grant  execute on function public.ack_goal_end(uuid) to authenticated;

select 'end goal early' as check, count(*) from information_schema.columns where table_schema='public' and table_name='engagements' and column_name in ('ended_by','end_kind','end_reason','end_note','end_ack_at');
