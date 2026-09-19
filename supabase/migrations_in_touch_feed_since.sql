-- CN-13: In Touch feed shows only wins AFTER the connection was made.
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
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'user_id', ev.user_id, 'display_name', pr.display_name, 'avatar_path', pr.avatar_path, 'avatar_initials', pr.avatar_initials,
           'kind', ev.kind, 'ref', ev.ref, 'at', ev.at, 'text', ev.text,
           'congratulated', exists (select 1 from public.celebrations c where c.from_user = auth.uid() and c.to_user = ev.user_id and c.event_kind = ev.kind and c.event_ref = ev.ref)
         ) order by ev.at desc), '[]'::jsonb)
    from ev join public.profiles pr on pr.id = ev.user_id;
$$;
select 'in_touch_feed updated' as check;
