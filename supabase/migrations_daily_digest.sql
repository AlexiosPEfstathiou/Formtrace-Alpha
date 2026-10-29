-- =====================================================================
-- FormTrace — Item DI: the morning summary push, ~08:00 in each user's own timezone.
-- Needs: migrations_push.sql (CE) run, and pg_cron (enabled below, or Dashboard →
-- Database → Extensions → pg_cron). Sends through push_outbox → push-send, like every push.
-- =====================================================================

-- 1. each user's timezone (IANA name from the phone; refreshed at every sign-in)
alter table public.profiles add column if not exists tz text;
create or replace function public.set_my_tz(p_tz text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_tz is null or not exists (select 1 from pg_timezone_names where name = p_tz) then return; end if;
  update public.profiles set tz = p_tz where id = auth.uid() and tz is distinct from p_tz;
end; $$;
revoke execute on function public.set_my_tz(text) from public;
grant  execute on function public.set_my_tz(text) to authenticated;

-- 2. one summary per user per local day
create table if not exists public.daily_digest_log (
  user_id    uuid not null references public.profiles(id) on delete cascade,
  local_date date not null,
  sent_at    timestamptz not null default now(),
  primary key (user_id, local_date)
);
alter table public.daily_digest_log enable row level security;   -- service role only

-- 3. compose one user's summary (title, body) for their local date
create or replace function public.compose_daily_digest(p_user uuid, p_day date)
returns table (title text, body text, url text) language plpgsql stable security definer set search_path = public as $$
declare r record; today_n int; today_name text; left_n int; wk date := date_trunc('week', p_day)::date;
  kcal int; prot int; ate_y boolean; weighed boolean; parts text[] := '{}'; rem text[] := '{}'; t text;
  reviews int; call_t text;
begin
  select role into r from public.profiles where id = p_user;
  if coalesce(r.role,'trainee') = 'coach' then
    select count(*) into reviews from public.submissions s
      join public.assigned_workouts aw on aw.id = s.assigned_id
      join public.engagements e on e.id = aw.engagement_id
     where e.coach_id = p_user and e.status = 'active'
       and not exists (select 1 from public.reviews rv where rv.submission_id = s.id);
    select left(min(cp.start_time)::text,5) into call_t from public.call_proposals cp
      join public.engagements e on e.id = cp.engagement_id
     where e.coach_id = p_user and cp.status = 'accepted' and cp.proposed_date = p_day;
    t := case when reviews > 0 then reviews || ' review' || case when reviews = 1 then '' else 's' end || ' waiting' else 'Good morning, coach' end;
    return query select t,
      coalesce(case when call_t is not null then 'Call today at ' || call_t || '. ' end, '')
      || case when reviews > 0 then 'Your trainees are waiting on your feedback.' else 'No reviews waiting - a clear start.' end,
      '/#coach'::text;
    return;
  end if;

  -- trainee: today's sessions on active goals
  select count(*), min(coalesce(aw.snapshot->>'name', aw.snapshot->>'title')) into today_n, today_name
    from public.assigned_workouts aw join public.engagements e on e.id = aw.engagement_id
   where e.trainee_id = p_user and e.status = 'active' and aw.status = 'assigned' and aw.due_date = p_day;
  select count(*) into left_n
    from public.assigned_workouts aw join public.engagements e on e.id = aw.engagement_id
   where e.trainee_id = p_user and e.status = 'active' and aw.status = 'assigned'
     and (aw.due_date is null or aw.due_date between wk and wk + 6);
  -- this week's nutrition goal (the latest set on or before this week, carried forward)
  select mg.kcal, mg.protein_g into kcal, prot from public.macro_goals mg join public.engagements e on e.id = mg.engagement_id
   where e.trainee_id = p_user and e.status = 'active' and mg.week_start <= wk order by mg.week_start desc limit 1;
  select exists (select 1 from public.logs where trainee_id = p_user and log_date = p_day - 1 and (kcal is not null or protein_g is not null)) into ate_y;
  select exists (select 1 from public.logs where trainee_id = p_user and log_date = p_day and weight_kg is not null) into weighed;

  t := case when today_n = 1 then 'Today: ' || coalesce(today_name, 'your session')
            when today_n > 1 then 'Today: ' || today_n || ' sessions'
            when left_n > 0 then left_n || ' session' || case when left_n = 1 then '' else 's' end || ' left this week'
            when exists (select 1 from public.engagements where trainee_id = p_user and status = 'active') then 'Rest day today'
            else 'Good morning' end;
  if kcal is not null or prot is not null then
    parts := parts || (concat_ws(' · ', case when kcal is not null then to_char(kcal,'FM99,999') || ' kcal' end, case when prot is not null then prot || ' g protein' end));
  end if;
  if not ate_y then rem := rem || 'log yesterday''s food'::text; end if;
  if not weighed then rem := rem || 'weigh in this morning'::text; end if;
  if array_length(rem,1) > 0 then
    parts := parts || (upper(left(array_to_string(rem,' and '),1)) || substr(array_to_string(rem,' and '),2) || '.');
  end if;
  return query select t, coalesce(nullif(array_to_string(parts, '. '), ''), 'Have a good day.'), '/#trainee-home'::text;
end; $$;

-- 4. the sender: everyone whose local hour is 8 and who has not had today's summary
create or replace function public.send_daily_digests()
returns integer language plpgsql security definer set search_path = public as $$
declare u record; d record; n int := 0;
begin
  if to_regclass('public.push_outbox') is null then return 0; end if;
  for u in
    select p.id, (now() at time zone p.tz)::date as local_day
      from public.profiles p
     where p.tz is not null
       and extract(hour from (now() at time zone p.tz)) = 8
       and coalesce((p.push_prefs->>'daily')::boolean, true)
       and exists (select 1 from public.push_subscriptions s where s.user_id = p.id)
       and not exists (select 1 from public.daily_digest_log l where l.user_id = p.id and l.local_date = (now() at time zone p.tz)::date)
  loop
    insert into public.daily_digest_log (user_id, local_date) values (u.id, u.local_day) on conflict do nothing;
    if not found then continue; end if;
    select * into d from public.compose_daily_digest(u.id, u.local_day);
    insert into public.push_outbox (to_user, kind, title, body, url) values (u.id, 'daily', d.title, d.body, d.url);
    n := n + 1;
  end loop;
  return n;
end; $$;
revoke execute on function public.send_daily_digests() from public;

-- 5. schedule: every 15 minutes (idempotent per user per local day)
create extension if not exists pg_cron;
select cron.unschedule('formtrace-daily-digest') where exists (select 1 from cron.job where jobname = 'formtrace-daily-digest');
select cron.schedule('formtrace-daily-digest', '*/15 * * * *', $$select public.send_daily_digests();$$);

-- preview any user's summary without sending:  select * from public.compose_daily_digest('<user uuid>', current_date);
select jobname, schedule from cron.job where jobname = 'formtrace-daily-digest';
