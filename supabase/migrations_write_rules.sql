-- Item GI-1 (security review 2026-11-10): tighter write rules for reviews, ratings, submissions, assigned workouts,
-- fee overrides and the streak counter. Each rule now matches exactly what the app does.
--   reviews            a coach may write a review only for a submission from one of their OWN goals (was: any submission)
--   ratings            only a party of that goal, about the OTHER party, once the goal is completed or ended (was: anyone, any goal)
--   submissions        a trainee may submit only against their OWN assigned workout (was: any assigned workout)
--   assigned_workouts  read: both parties. add: the coach only, as 'assigned'. change: both (columns already limited to
--                      draft / opened). remove: the coach only, and only a session that has NOT been started - a submitted
--                      session is the evidence the refund rules rely on, so it can no longer be deleted. (was: either
--                      party could add or delete any of them)
--   fee_overrides      readable by the coach concerned and by admins (was: every signed-in user)
--   profiles.streak_count  no longer editable by the user (the app never wrote it; the streak functions still maintain it)
-- Policies add up, so a looser old policy left in place would defeat a new one: every existing policy of the kinds
-- being replaced is dropped by reading the live catalog, whatever it is called. Database functions and the service role
-- are unaffected. Safe to re-run.

do $$
declare p record;
begin
  for p in select policyname, tablename from pg_policies where schemaname = 'public' and (
             (tablename = 'reviews'           and cmd in ('INSERT','ALL'))
          or (tablename = 'ratings'           and cmd in ('INSERT','ALL'))
          or (tablename = 'submissions'       and cmd in ('INSERT','ALL'))
          or (tablename = 'assigned_workouts')
          or (tablename = 'fee_overrides'     and cmd in ('SELECT','ALL')))
  loop
    execute format('drop policy %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

create policy "coach reviews own trainees" on public.reviews for insert to authenticated
  with check (coach_id = auth.uid() and exists (
    select 1 from public.submissions s
      join public.assigned_workouts a on a.id = s.assigned_id
      join public.engagements e on e.id = a.engagement_id
     where s.id = submission_id and e.coach_id = auth.uid()));

create policy "parties rate each other after the goal" on public.ratings for insert to authenticated
  with check (rater_id = auth.uid() and exists (
    select 1 from public.engagements e
     where e.id = engagement_id and e.status in ('completed', 'ended')
       and ((e.trainee_id = auth.uid() and e.coach_id = ratee_id) or (e.coach_id = auth.uid() and e.trainee_id = ratee_id))));

create policy "trainee submits own sessions" on public.submissions for insert to authenticated
  with check (trainee_id = auth.uid() and exists (
    select 1 from public.assigned_workouts a join public.engagements e on e.id = a.engagement_id
     where a.id = assigned_id and e.trainee_id = auth.uid()));

create policy "assigned readable by parties" on public.assigned_workouts for select to authenticated
  using (exists (select 1 from public.engagements e where e.id = engagement_id and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())));
create policy "coach assigns sessions" on public.assigned_workouts for insert to authenticated
  with check (status = 'assigned' and exists (select 1 from public.engagements e where e.id = engagement_id and e.coach_id = auth.uid()));
create policy "parties update assigned" on public.assigned_workouts for update to authenticated
  using (exists (select 1 from public.engagements e where e.id = engagement_id and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())))
  with check (exists (select 1 from public.engagements e where e.id = engagement_id and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())));
create policy "coach removes unstarted sessions" on public.assigned_workouts for delete to authenticated
  using (status = 'assigned' and exists (select 1 from public.engagements e where e.id = engagement_id and e.coach_id = auth.uid()));

create policy "fee override visible to its coach and admins" on public.fee_overrides for select to authenticated
  using (coach_id = auth.uid() or public.is_admin());

revoke update (streak_count) on public.profiles from authenticated;

-- Check: expect  reviews_insert 1 | ratings_insert 1 | submissions_insert 1 | assigned_policies 4 | fee_select 1 | streak_editable false
select (select count(*) from pg_policies where schemaname = 'public' and tablename = 'reviews'       and cmd in ('INSERT','ALL')) as reviews_insert,
       (select count(*) from pg_policies where schemaname = 'public' and tablename = 'ratings'       and cmd in ('INSERT','ALL')) as ratings_insert,
       (select count(*) from pg_policies where schemaname = 'public' and tablename = 'submissions'   and cmd in ('INSERT','ALL')) as submissions_insert,
       (select count(*) from pg_policies where schemaname = 'public' and tablename = 'assigned_workouts')                          as assigned_policies,
       (select count(*) from pg_policies where schemaname = 'public' and tablename = 'fee_overrides' and cmd in ('SELECT','ALL')) as fee_select,
       has_column_privilege('authenticated', 'public.profiles', 'streak_count', 'UPDATE')                                           as streak_editable;
