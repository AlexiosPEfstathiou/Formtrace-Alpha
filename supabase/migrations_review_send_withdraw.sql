-- GQ / GR / GS (owner, 2026-11-13). Safe to re-run.
-- GQ: the review push links to that workout's review ("/#review=<assigned workout id>").
-- GR: a review reaches the trainee only through send_review(), which the app calls after the coach confirms a summary.
--     Coaches can no longer insert reviews directly.
-- GS: withdraw_review() for one hour after sending (the hour restarts each time it is sent again). The row is kept with
--     withdrawn_at, hidden from the trainee; the workout goes back to the coach's queue and the app pre-fills it.
--     Owner: the trainee is not told; achievements are not rolled back (a re-send updates the same row, so nothing counts twice).

alter table public.reviews add column if not exists sent_at timestamptz;
alter table public.reviews add column if not exists withdrawn_at timestamptz;
update public.reviews set sent_at = created_at where sent_at is null;
alter table public.reviews alter column sent_at set default now();

-- GQ: push with a link to the reviewed workout
create or replace function public.push_on_review() returns trigger
language plpgsql security definer set search_path = public as $$
declare t uuid; a uuid;
begin
  begin
    select s.trainee_id, s.assigned_id into t, a from public.submissions s where s.id = new.submission_id;
    if t is not null then
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (t, 'review', '📝 Your coach reviewed a workout', 'Tags, notes and voice-over are ready',
              case when a is not null then '/#review=' || a else '/#trainee-home' end);
    end if;
  exception when others then
    raise warning 'push_on_review skipped: %', sqlerrm;   -- never block the write this push describes
  end;
  return new;
end $$;

-- GR: no direct inserts - send_review is the only way in
drop policy if exists "coach reviews own trainees" on public.reviews;

-- GS: the trainee does not see a withdrawn review; the coach still does (to pre-fill)
drop policy if exists "parties read reviews" on public.reviews;
create policy "parties read reviews" on public.reviews for select using (
  coach_id = auth.uid()
  or (withdrawn_at is null and exists (select 1 from public.submissions s
                                        where s.id = reviews.submission_id and s.trainee_id = auth.uid())));

create or replace function public.send_review(p_submission uuid, p_overall text, p_per_set jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_assigned uuid; v_trainee uuid; v_coach uuid; v_status text; v_id uuid;
begin
  select s.assigned_id, s.trainee_id, e.coach_id, a.status into v_assigned, v_trainee, v_coach, v_status
    from public.submissions s
    join public.assigned_workouts a on a.id = s.assigned_id
    join public.engagements e on e.id = a.engagement_id
   where s.id = p_submission;
  if v_coach is null then raise exception 'workout not found'; end if;
  if v_coach <> auth.uid() then raise exception 'not your trainee'; end if;
  if v_status <> 'submitted' then raise exception 'nothing to review'; end if;
  if jsonb_typeof(coalesce(p_per_set, '[]'::jsonb)) <> 'array' then raise exception 'bad review'; end if;

  -- a review already on this workout (withdrawn, or left behind) is sent again in place
  select r.id into v_id from public.reviews r join public.submissions s on s.id = r.submission_id
   where s.assigned_id = v_assigned order by r.created_at desc limit 1;
  if v_id is not null then
    update public.reviews
       set submission_id = p_submission, overall = p_overall, per_set = coalesce(p_per_set, '[]'::jsonb),
           withdrawn_at = null, sent_at = now()
     where id = v_id;
    if to_regclass('public.push_outbox') is not null then
      begin
        insert into public.push_outbox (to_user, kind, title, body, url)
        values (v_trainee, 'review', '📝 Your coach reviewed a workout', 'Tags, notes and voice-over are ready', '/#review=' || v_assigned);
      exception when others then raise warning 'send_review push skipped: %', sqlerrm; end;
    end if;
  else
    insert into public.reviews (submission_id, coach_id, overall, per_set, sent_at)
    values (p_submission, auth.uid(), p_overall, coalesce(p_per_set, '[]'::jsonb), now())
    returning id into v_id;   -- push_on_review and the achievement trigger fire here
  end if;

  update public.assigned_workouts set status = 'reviewed', opened = false where id = v_assigned;
  return v_id;
end $$;

create or replace function public.withdraw_review(p_review uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare r public.reviews; v_assigned uuid;
begin
  select * into r from public.reviews where id = p_review;
  if not found then raise exception 'review not found'; end if;
  if r.coach_id <> auth.uid() then raise exception 'not your review'; end if;
  if r.withdrawn_at is not null then raise exception 'this review is already withdrawn'; end if;
  if coalesce(r.sent_at, r.created_at) < now() - interval '1 hour' then
    raise exception 'A review can be withdrawn only within an hour of sending it';
  end if;
  select assigned_id into v_assigned from public.submissions where id = r.submission_id;
  update public.reviews set withdrawn_at = now() where id = p_review;
  update public.assigned_workouts set status = 'submitted', opened = true where id = v_assigned and status = 'reviewed';
  return v_assigned;
end $$;

revoke execute on function public.send_review(uuid, text, jsonb) from public, anon, authenticated;
grant  execute on function public.send_review(uuid, text, jsonb) to authenticated;
revoke execute on function public.withdraw_review(uuid) from public, anon, authenticated;
grant  execute on function public.withdraw_review(uuid) to authenticated;

-- withdrawn notes do not show in the per-exercise note history (EZ-6 / 6b)
do $$
declare src text;
begin
  src := pg_get_functiondef('public.exercise_notes(uuid, uuid[], text[])'::regprocedure);
  if position('r.withdrawn_at is null' in src) = 0 and position('where s.trainee_id = p_trainee' in src) > 0 then
    src := replace(src, 'where s.trainee_id = p_trainee', 'where s.trainee_id = p_trainee and r.withdrawn_at is null');
    execute src;
  end if;
end $$;

-- Check: expect  columns 2 | insert_policies 0 | functions 2 | push_link 1 | notes_filtered 1
select
  (select count(*) from information_schema.columns where table_name = 'reviews' and column_name in ('sent_at', 'withdrawn_at')) as columns,
  (select count(*) from pg_policies where tablename = 'reviews' and cmd = 'INSERT') as insert_policies,
  (select count(*) from pg_proc where proname in ('send_review', 'withdraw_review')
     and has_function_privilege('authenticated', oid, 'execute')) as functions,
  (select count(*) from pg_proc where proname = 'push_on_review' and prosrc like '%/#review=%') as push_link,
  (select count(*) from pg_proc where proname = 'exercise_notes' and prosrc like '%r.withdrawn_at is null%') as notes_filtered;
