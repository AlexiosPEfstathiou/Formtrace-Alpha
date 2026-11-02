-- =====================================================================
-- FormTrace — two owner decisions of 2026-11-02, built together:
--  (1) a COACH can end a goal early. Under Stripe escrow no automatic refund is sent:
--      the trainee chooses CREDIT (the full unused amount, its processing share included)
--      or a REFUND of the unused price less Stripe's non-returned card fee (costs only).
--      No choice within 14 days = credit (daily job).
--  (2) fast reviews: a "Reviews within a day" mark (>= 80 % of sessions reviewed within
--      24 h over 30 days, at least 5), and a 7-day release hold instead of 14 for a week
--      whose every session was reviewed within 24 h.
-- Run AFTER migrations_refunds*.sql and migrations_weekly_release.sql. Safe to re-run.
-- =====================================================================

-- (1a) a third way a goal can end
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid = 'public.engagements'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%end_kind%' loop
    execute format('alter table public.engagements drop constraint %I', c);
  end loop;
end $$;
alter table public.engagements add constraint engagements_end_kind_check
  check (end_kind is null or end_kind in ('achieved','cancelled','coach_ended'));

-- (1b) the trainee's choice, and the credit ledger (+ kept, - used)
create table if not exists public.goal_end_choices (
  engagement_id    uuid primary key references public.engagements(id) on delete cascade,
  trainee_id       uuid not null references public.profiles(id) on delete cascade,
  coach_id         uuid not null references public.profiles(id) on delete cascade,
  price_cents      bigint not null,                 -- unused (unreleased) price
  processing_cents bigint not null default 0,       -- its share of the processing line
  currency         text not null,
  status           text not null default 'pending' check (status in ('pending','credit','refund')),
  default_at       timestamptz not null default now() + interval '14 days',
  chosen_at        timestamptz,
  chosen_by        text,                            -- 'trainee' | 'default'
  created_at       timestamptz not null default now()
);
alter table public.goal_end_choices enable row level security;
drop policy if exists "parties read goal end choice" on public.goal_end_choices;
create policy "parties read goal end choice" on public.goal_end_choices for select to authenticated
  using (trainee_id = auth.uid() or coach_id = auth.uid());

create table if not exists public.trainee_credits (
  id                uuid primary key default gen_random_uuid(),
  trainee_id        uuid not null references public.profiles(id) on delete cascade,
  amount_cents      bigint not null,                -- + credit kept, - credit used
  currency          text not null,
  source_engagement uuid references public.engagements(id) on delete set null,
  used_engagement   uuid references public.engagements(id) on delete set null,
  note              text,
  created_at        timestamptz not null default now()
);
alter table public.trainee_credits enable row level security;
drop policy if exists "trainee reads own credits" on public.trainee_credits;
create policy "trainee reads own credits" on public.trainee_credits for select to authenticated using (trainee_id = auth.uid());

create or replace function public.my_credit_balance() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(currency, total), '{}'::jsonb)
    from (select currency, sum(amount_cents) as total from public.trainee_credits where trainee_id = auth.uid() group by currency having sum(amount_cents) <> 0) x;
$$;
revoke execute on function public.my_credit_balance() from public;
grant  execute on function public.my_credit_balance() to authenticated;

create or replace function public._eur(p_cents bigint) returns text language sql immutable as $$
  select '€' || to_char(coalesce(p_cents,0) / 100.0, 'FM999999990.00');
$$;

-- (1c) when a coach-ended Stripe goal ends: cancel queued releases, record the choice, tell the trainee
create or replace function public.queue_end_choice(p_eng uuid) returns void
language plpgsql security definer set search_path = public as $$
declare e record; v_price bigint; v_released bigint; v_un bigint; v_proc bigint;
begin
  select * into e from public.engagements where id = p_eng;
  if not found or e.deposit_at is null then return; end if;
  if exists (select 1 from public.goal_end_choices where engagement_id = p_eng)
     or exists (select 1 from public.payment_refunds where engagement_id = p_eng) then return; end if;
  update public.payment_releases set status = 'cancelled', error = 'goal ended by the coach'
   where engagement_id = p_eng and status = 'queued';
  if coalesce(e.deposit_amount, 0) = 0 then return; end if;                -- comp deposit: nothing to give back
  v_price := e.deposit_amount - coalesce(e.deposit_processing, 0);
  select coalesce(sum(gross_cents), 0) into v_released from public.payment_releases
   where engagement_id = p_eng and status in ('sent','skipped');
  v_un := greatest(0, v_price - v_released);
  if v_un = 0 then return; end if;
  v_proc := case when v_price > 0 then round(coalesce(e.deposit_processing, 0) * v_un::numeric / v_price) else 0 end;
  insert into public.goal_end_choices (engagement_id, trainee_id, coach_id, price_cents, processing_cents, currency)
  values (p_eng, e.trainee_id, e.coach_id, v_un, v_proc, coalesce(e.deposit_currency, 'eur'));
  if to_regclass('public.push_outbox') is not null then
    insert into public.push_outbox (to_user, kind, title, body, url)
    values (e.trainee_id, 'offer', 'Your coach ended "' || coalesce(e.goal_title, 'your goal') || '"',
            'Choose: keep ' || public._eur(v_un + v_proc) || ' as credit for your next goal, or a refund of ' || public._eur(v_un)
            || ' to your card. No choice in 14 days = credit.', '/#listings');
  end if;
end; $$;
revoke execute on function public.queue_end_choice(uuid) from public;

-- the existing trigger function: coach-ended goals go to the choice, every other ending to queue_refund (unchanged)
create or replace function public.refund_on_end() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'ended' and old.status is distinct from 'ended' and new.deposit_at is not null then
    begin
      if new.end_kind = 'coach_ended' then perform public.queue_end_choice(new.id);
      else perform public.queue_refund(new.id); end if;
    exception when others then raise warning 'refund_on_end %: %', new.id, sqlerrm; end;
  end if;
  return new;
end $$;

-- (1d) the coach ends the goal
create or replace function public.coach_end_goal(p_eng uuid, p_reason text, p_note text default null)
returns public.engagements language plpgsql security definer set search_path = public as $$
declare e public.engagements;
begin
  select * into e from public.engagements where id = p_eng;
  if not found then raise exception 'goal not found'; end if;
  if e.coach_id <> auth.uid() then raise exception 'only the coach of this goal can end it'; end if;
  if e.status <> 'active' then raise exception 'this goal is not active'; end if;
  update public.engagements
     set status = 'ended', completed_at = now(), ended_by = auth.uid(), end_kind = 'coach_ended',
         end_reason = left(coalesce(p_reason, ''), 60), end_note = nullif(left(coalesce(p_note, ''), 500), '')
   where id = p_eng returning * into e;
  delete from public.assigned_workouts where engagement_id = p_eng and status = 'assigned';
  -- a goal paid directly (no Stripe deposit): just tell the trainee; the choice push covers Stripe goals
  if e.deposit_at is null and to_regclass('public.push_outbox') is not null then
    begin
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (e.trainee_id, 'offer', public._name_of(e.coach_id) || ' ended "' || coalesce(e.goal_title, 'your goal') || '"',
              coalesce(nullif(e.end_note, ''), 'Sessions not started have been removed.'), '/#listings');
    exception when others then raise warning 'coach_end_goal push skipped: %', sqlerrm; end;
  end if;
  return e;
end; $$;
revoke execute on function public.coach_end_goal(uuid, text, text) from public;
grant  execute on function public.coach_end_goal(uuid, text, text) to authenticated;

-- (1e) applying a choice (the trainee's, or the default)
create or replace function public._apply_end_choice(p_eng uuid, p_choice text, p_by text) returns void
language plpgsql security definer set search_path = public as $$
declare c record;
begin
  select * into c from public.goal_end_choices where engagement_id = p_eng for update;
  if not found or c.status <> 'pending' then return; end if;
  if p_choice = 'credit' then
    insert into public.trainee_credits (trainee_id, amount_cents, currency, source_engagement, note)
    values (c.trainee_id, c.price_cents + c.processing_cents, c.currency, p_eng,
            case when p_by = 'default' then 'coach ended the goal - no choice in 14 days, kept as credit' else 'coach ended the goal - kept as credit' end);
  elsif p_choice = 'refund' then
    insert into public.payment_refunds (engagement_id, price_cents, processing_cents, amount_cents, currency, reason, rule, status, sent_at)
    values (p_eng, c.price_cents, 0, c.price_cents, c.currency, 'coach_ended', 'coach_ended',
            case when c.price_cents > 0 then 'queued' else 'skipped' end, case when c.price_cents > 0 then null else now() end);
  else
    raise exception 'choose credit or refund';
  end if;
  update public.goal_end_choices set status = p_choice, chosen_at = now(), chosen_by = p_by where engagement_id = p_eng;
  if to_regclass('public.push_outbox') is not null then
    begin
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (c.coach_id, 'offer', public._name_of(c.trainee_id) || case when p_choice = 'credit' then ' kept the unused weeks as credit' else ' chose a refund' end,
              'Weeks already released to you are unaffected.', '/#coach');
      if p_by = 'default' then
        insert into public.push_outbox (to_user, kind, title, body, url)
        values (c.trainee_id, 'offer', public._eur(c.price_cents + c.processing_cents) || ' kept as credit',
                'No choice was made within 14 days - the credit goes towards your next goal.', '/#listings');
      end if;
    exception when others then raise warning '_apply_end_choice push skipped: %', sqlerrm; end;
  end if;
end; $$;
revoke execute on function public._apply_end_choice(uuid, text, text) from public;

create or replace function public.choose_goal_end(p_eng uuid, p_choice text) returns void
language plpgsql security definer set search_path = public as $$
declare c record;
begin
  select * into c from public.goal_end_choices where engagement_id = p_eng;
  if not found then raise exception 'there is nothing to choose for this goal'; end if;
  if c.trainee_id <> auth.uid() then raise exception 'only the trainee makes this choice'; end if;
  if c.status <> 'pending' then raise exception 'this choice has already been made'; end if;
  perform public._apply_end_choice(p_eng, p_choice, 'trainee');
end; $$;
revoke execute on function public.choose_goal_end(uuid, text) from public;
grant  execute on function public.choose_goal_end(uuid, text) to authenticated;

create or replace function public.apply_default_end_choices() returns integer
language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select engagement_id from public.goal_end_choices where status = 'pending' and default_at <= now() loop
    perform public._apply_end_choice(r.engagement_id, 'credit', 'default'); n := n + 1;
  end loop;
  return n;
end; $$;
revoke execute on function public.apply_default_end_choices() from public;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'formtrace-end-choice-defaults';
    perform cron.schedule('formtrace-end-choice-defaults', '23 4 * * *', 'select public.apply_default_end_choices()');
  end if;
end $$;

-- (2a) fast reviews
insert into public.platform_rates (key, value, note) values
  ('release_hold_fast_days', 7,  'EL: release hold for a week whose every session was reviewed within 24 h (owner, 2026-11-02)'),
  ('fast_review_share_pct', 80,  'EL: share of sessions reviewed within 24 h over 30 days for the "Reviews within a day" mark'),
  ('fast_review_min_reviews', 5, 'EL: sessions needed in 30 days before the mark can show')
on conflict (key) do nothing;

create or replace function public.week_reviewed_fast(p_eng uuid, p_week date) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.assigned_workouts aw join public.submissions s on s.assigned_id = aw.id
                  where aw.engagement_id = p_eng and aw.due_date between p_week and p_week + 6)
     and not exists (select 1 from public.assigned_workouts aw join public.submissions s on s.assigned_id = aw.id
                      where aw.engagement_id = p_eng and aw.due_date between p_week and p_week + 6
                        and not exists (select 1 from public.reviews r where r.submission_id = s.id and r.created_at <= s.created_at + interval '24 hours'));
$$;
revoke execute on function public.week_reviewed_fast(uuid, date) from public;

create or replace function public.fast_reviewer_coaches() returns setof uuid
language sql stable security definer set search_path = public as $$
  select e.coach_id
    from public.submissions s
    join public.assigned_workouts aw on aw.id = s.assigned_id
    join public.engagements e on e.id = aw.engagement_id
   where s.created_at >= now() - interval '30 days'
     and (s.created_at <= now() - interval '24 hours' or exists (select 1 from public.reviews r where r.submission_id = s.id))
   group by e.coach_id
  having count(*) >= coalesce((select value from public.platform_rates where key = 'fast_review_min_reviews'), 5)
     and 100.0 * count(*) filter (where exists (select 1 from public.reviews r where r.submission_id = s.id and r.created_at <= s.created_at + interval '24 hours'))
         / count(*) >= coalesce((select value from public.platform_rates where key = 'fast_review_share_pct'), 80);
$$;
revoke execute on function public.fast_reviewer_coaches() from public;
grant  execute on function public.fast_reviewer_coaches() to authenticated;

-- (2b) the weekly release job: copied from migrations_weekly_release.sql, only the hold changescreate or replace function public.queue_weekly_releases()
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_hold   integer := coalesce((select value::int from platform_rates where key = 'release_hold_days'), 14);
  v_fast   integer := coalesce((select value::int from platform_rates where key = 'release_hold_fast_days'), 7);   -- EL: every review within 24 h
  v_comm   numeric := coalesce((select value from platform_rates where key = 'coach_commission_pct'), 0);
  v_n      integer := 0;
  r        record;
  v_gross  bigint; v_comm_c bigint; v_amount bigint; v_released bigint; v_cap bigint;
begin
  for r in
    select e.id as engagement_id, e.coach_id, e.deposit_amount, e.deposit_processing, e.deposit_currency,
           o.rate_per_workout_cents as weekly_cents, wc.week_start, wc.neutral,
           (p.founding_at is not null) as founding
      from engagements e
      join offers o on o.id = e.offer_id
      join profiles p on p.id = e.coach_id
      join week_closures wc on wc.engagement_id = e.id
     where e.deposit_at is not null                                          -- paid through Stripe (or comp)
       and e.status in ('active','completed','ended')
       and wc.closed_at <= now() - make_interval(days => case when public.week_reviewed_fast(e.id, wc.week_start) then least(v_fast, v_hold) else v_hold end)   -- the hold has passed (EL: shorter when every review landed within 24 h)
       and wc.week_start >= (e.deposit_at at time zone 'UTC')::date - 6      -- not before the deposit's week
       and not exists (select 1 from payment_releases pr where pr.engagement_id = e.id and pr.week_start = wc.week_start)
       and not exists (select 1 from assigned_workouts aw                   -- DELIVERED: nothing submitted and unreviewed
                        where aw.engagement_id = e.id and aw.status = 'submitted'
                          and aw.due_date between wc.week_start and wc.week_start + 6)
     order by e.id, wc.week_start
  loop
    if r.neutral or coalesce(r.weekly_cents, 0) <= 0 then
      continue;                                                              -- neutral week: no release, money stays for DZ
    end if;
    v_gross := r.weekly_cents;
    if coalesce(r.deposit_amount, 0) = 0 then                                -- ED comp: the step moves, no money
      insert into payment_releases (engagement_id, week_start, gross_cents, commission_cents, amount_cents, currency, status, sent_at)
      values (r.engagement_id, r.week_start, v_gross, 0, 0, coalesce(r.deposit_currency, 'eur'), 'skipped', now());
      v_n := v_n + 1; continue;
    end if;
    v_comm_c  := case when r.founding then 0 else round(v_gross * v_comm / 100) end;
    v_amount  := v_gross - v_comm_c;
    -- never release more than the price part of the deposit (processing line excluded, EA)
    select coalesce(sum(gross_cents), 0) into v_released from payment_releases
     where engagement_id = r.engagement_id and status in ('queued','sent');
    v_cap := r.deposit_amount - coalesce(r.deposit_processing, 0) - v_released;
    if v_cap <= 0 then continue; end if;
    if v_gross > v_cap then v_gross := v_cap; v_comm_c := case when r.founding then 0 else round(v_gross * v_comm / 100) end; v_amount := v_gross - v_comm_c; end if;
    insert into payment_releases (engagement_id, week_start, gross_cents, commission_cents, amount_cents, currency)
    values (r.engagement_id, r.week_start, v_gross, v_comm_c, v_amount, r.deposit_currency);
    v_n := v_n + 1;
  end loop;

  -- re-fire the webhook once a day for releases still waiting on the coach's Stripe onboarding
  update payment_releases set attempts = attempts
   where status = 'queued' and error is not null and created_at < now() - interval '1 day'
     and (nudged_at is null or nudged_at < now() - interval '1 day');
  return v_n;
end $$;
revoke execute on function public.queue_weekly_releases() from public;

select (select count(*) from pg_proc where proname in ('coach_end_goal','choose_goal_end','apply_default_end_choices','queue_end_choice','fast_reviewer_coaches','week_reviewed_fast')) as functions,
       (select count(*) from information_schema.tables where table_schema = 'public' and table_name in ('goal_end_choices','trainee_credits')) as tables,
       (select value from public.platform_rates where key = 'release_hold_fast_days') as fast_hold_days;