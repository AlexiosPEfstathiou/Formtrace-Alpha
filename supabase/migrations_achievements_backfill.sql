-- =====================================================================
-- FormTrace — CY backfill: award achievements existing trainees already earned, silently for
-- friends (no feed, no push); Notifications chips remain. Run ONCE, before CE push goes live.
-- =====================================================================
alter table public.user_achievements add column if not exists backfilled boolean not null default false;

do $$ declare r record; begin
  for r in select id from public.profiles where coalesce(role,'trainee') = 'trainee' loop
    perform public.check_achievements(r.id);
  end loop;
end $$;

update public.user_achievements set backfilled = true where earned_at > now() - interval '10 minutes';
do $$ begin
  if to_regclass('public.push_outbox') is not null then   -- CE may not be installed yet
    delete from public.push_outbox where kind = 'achievement' and sent_at is null and created_at > now() - interval '10 minutes';
  end if;
end $$;

create or replace function public.in_touch_feed()
returns jsonb language sql stable security definer set search_path = public as $$
  with mine as (
    select case when a = auth.uid() then b else a end as other, coalesce(confirmed_at, created_at) as since
      from public.connections where status='confirmed' and (a = auth.uid() or b = auth.uid())
  ),
  ev as (
    select p.trainee_id as user_id, 'pb' as kind, p.id::text as ref, p.achieved_at as at,
           p.exercise_name || ' ' || case when p.weight_kg is not null then p.weight_kg || ' kg × ' || p.reps else p.reps || ' reps' end as text
      from public.personal_bests p join mine m on m.other = p.trainee_id
     where p.achieved_at > m.since and p.achieved_at > now() - interval '30 days'
    union all
    select e.trainee_id, 'goal', e.id::text, e.completed_at, 'Completed "' || coalesce(e.goal_title,'a goal') || '"'
      from public.engagements e join mine m on m.other = e.trainee_id
     where e.status = 'completed' and e.completed_at > m.since and e.completed_at > now() - interval '30 days'
    union all
    select ua.user_id, 'achievement', ua.code, ua.earned_at, a.icon || ' ' || a.title
      from public.user_achievements ua join public.achievements a on a.code = ua.code and a.approved join mine m on m.other = ua.user_id
     where not ua.backfilled and ua.earned_at > m.since and ua.earned_at > now() - interval '30 days'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', ev.user_id, 'display_name', pr.display_name, 'avatar_path', pr.avatar_path, 'avatar_initials', pr.avatar_initials,
           'kind', ev.kind, 'ref', ev.ref, 'at', ev.at, 'text', ev.text,
           'congratulated', exists (select 1 from public.celebrations c where c.from_user = auth.uid() and c.to_user = ev.user_id and c.event_kind = ev.kind and c.event_ref = ev.ref)
         ) order by ev.at desc), '[]'::jsonb)
    from ev join public.profiles pr on pr.id = ev.user_id;
$$;

create or replace function public.congratulate_all(p_to uuid, p_text text default 'this week''s progress')
returns integer language plpgsql security definer set search_path = public as $$
declare n integer := 0; r record; wk date := date_trunc('week', current_date)::date;
begin
  if not public.are_connected(auth.uid(), p_to) then raise exception 'you are not connected'; end if;
  for r in
    select 'pb' as kind, p.id::text as ref from public.personal_bests p where p.trainee_id = p_to and p.achieved_at >= wk
    union all
    select 'goal', e.id::text from public.engagements e where e.trainee_id = p_to and e.status='completed' and e.completed_at >= wk
    union all
    select 'achievement', ua.code from public.user_achievements ua where ua.user_id = p_to and ua.earned_at >= wk and not ua.backfilled
  loop
    insert into public.celebrations (from_user, to_user, event_kind, event_ref, event_text, seen_at)
    values (auth.uid(), p_to, r.kind, r.ref, '(part of the week''s congratulation)', now())
    on conflict do nothing;
    if found then n := n + 1; end if;
  end loop;
  insert into public.celebrations (from_user, to_user, event_kind, event_ref, event_text)
  values (auth.uid(), p_to, 'week', wk::text, left(coalesce(p_text,'this week''s progress'), 120))
  on conflict (from_user, to_user, event_kind, event_ref) do update set created_at = now(), seen_at = null, event_text = excluded.event_text;
  return n;
end; $$;

select count(*) as backfilled from public.user_achievements where backfilled;