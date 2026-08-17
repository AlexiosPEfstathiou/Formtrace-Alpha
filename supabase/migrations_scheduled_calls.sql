-- =====================================================================
-- FormTrace — item G, scheduling mechanism for video calls
-- (the actual video-call technology — WebRTC vs. a paid provider — is a
-- separate, still-open decision; this is the propose/accept/counter
-- workflow that would sit in front of whichever gets chosen)
--
-- Design decisions made explicit here, not left implicit:
-- - Availability is a RECURRING WEEKLY pattern per person, not per-date —
--   the only realistic reading of "declare available hours".
-- - Availability is per-USER, not per-engagement — a coach has one real
--   schedule, not a different one for each trainee.
-- - The 24-hour deadline is a derived check against a stored timestamp,
--   same philosophy as every other "missed"/"expired" state in this app
--   (dayMissedWorkout, postpone deadlines) — not a cron job. This project
--   has no scheduled-job infrastructure; building one just for this would
--   be a separate, bigger decision than what was asked for here.
-- =====================================================================

create table if not exists public.availability_blocks (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  day_of_week int not null check (day_of_week between 0 and 6),  -- 0=Sunday, matches JS Date.getDay()
  start_time  time not null,
  end_time    time not null check (end_time > start_time),
  created_at  timestamptz not null default now()
);

create table if not exists public.call_proposals (
  id                 uuid primary key default gen_random_uuid(),
  engagement_id      uuid not null references public.engagements(id) on delete cascade,
  proposed_by        uuid not null references public.profiles(id) on delete cascade,
  proposed_date      date not null,
  start_time         time not null,
  end_time           time not null check (end_time > start_time),
  status             text not null default 'pending' check (status in ('pending','accepted','declined','countered')),
  parent_proposal_id uuid references public.call_proposals(id) on delete set null,
  created_at         timestamptz not null default now(),
  expires_at         timestamptz not null default (now() + interval '24 hours'),
  responded_at       timestamptz
);

alter table public.availability_blocks enable row level security;
alter table public.call_proposals      enable row level security;

-- Availability: a person manages their own blocks directly (no function
-- needed — there's no cross-party business logic to enforce here, unlike
-- proposals). Read is broader: the other party on an active engagement
-- needs to see it to know what's actually proposable.
create policy "manage own availability"
  on public.availability_blocks for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "read availability of an active engagement partner"
  on public.availability_blocks for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.engagements e
      where e.status = 'active'
        and ((e.coach_id = auth.uid() and e.trainee_id = availability_blocks.user_id)
          or (e.trainee_id = auth.uid() and e.coach_id = availability_blocks.user_id))
    )
  );

-- Proposals: read by both parties on the engagement. All writes go
-- through functions below — the accept/counter logic has real
-- role-specific rules (only the party who did NOT just act may respond)
-- that a raw insert/update policy can't express cleanly.
create policy "parties read call proposals"
  on public.call_proposals for select to authenticated
  using (exists (
    select 1 from public.engagements e
    where e.id = call_proposals.engagement_id
      and (e.coach_id = auth.uid() or e.trainee_id = auth.uid())
  ));

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
  v_dow int;
  v_row public.call_proposals;
begin
  if p_end_time <= p_start_time then raise exception 'end time must be after start time'; end if;
  if p_date < current_date then raise exception 'cannot propose a date in the past'; end if;

  select id, coach_id, trainee_id, status into v_eng
  from public.engagements where id = p_engagement_id;
  if not found then raise exception 'engagement not found'; end if;
  if v_eng.status <> 'active' then raise exception 'this engagement is not active'; end if;
  if uid <> v_eng.coach_id and uid <> v_eng.trainee_id then raise exception 'not a party to this engagement'; end if;

  -- day_of_week matching JS Date.getDay(): 0=Sunday. extract(dow from date)
  -- in Postgres already uses this exact convention, no offset needed.
  v_dow := extract(dow from p_date);

  -- Defense in depth: the client should already only offer genuinely
  -- overlapping slots, but the server is what actually guarantees a
  -- proposal can't name a time neither party actually declared free.
  if not exists (
    select 1 from public.availability_blocks
    where user_id = v_eng.coach_id and day_of_week = v_dow
      and start_time <= p_start_time and end_time >= p_end_time
  ) then raise exception 'that time is outside the coach''s declared availability'; end if;
  if not exists (
    select 1 from public.availability_blocks
    where user_id = v_eng.trainee_id and day_of_week = v_dow
      and start_time <= p_start_time and end_time >= p_end_time
  ) then raise exception 'that time is outside your own declared availability'; end if;

  -- Only one live thread per engagement — a fresh proposal (whether the
  -- opening one or a counter) supersedes whatever was pending before it.
  update public.call_proposals set status = 'declined', responded_at = now()
  where engagement_id = p_engagement_id and status = 'pending';

  insert into public.call_proposals (engagement_id, proposed_by, proposed_date, start_time, end_time)
  values (p_engagement_id, uid, p_date, p_start_time, p_end_time)
  returning * into v_row;
  return v_row;
end;
$$;

create or replace function public.respond_to_call_proposal(
  p_proposal_id uuid, p_action text,
  p_counter_date date default null, p_counter_start time default null, p_counter_end time default null
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
  if p_action not in ('accept','decline','counter') then raise exception 'invalid action'; end if;

  select * into v_prop from public.call_proposals where id = p_proposal_id;
  if not found then raise exception 'proposal not found'; end if;
  if v_prop.status <> 'pending' then raise exception 'this proposal is no longer pending'; end if;
  if v_prop.expires_at < now() then raise exception 'this proposal has expired'; end if;

  select id, coach_id, trainee_id into v_eng from public.engagements where id = v_prop.engagement_id;
  if v_prop.proposed_by = uid then raise exception 'you cannot respond to your own proposal'; end if;
  if uid <> v_eng.coach_id and uid <> v_eng.trainee_id then raise exception 'not a party to this engagement'; end if;

  if p_action = 'accept' then
    update public.call_proposals set status = 'accepted', responded_at = now() where id = p_proposal_id;
  elsif p_action = 'decline' then
    update public.call_proposals set status = 'declined', responded_at = now() where id = p_proposal_id;
  else -- counter: closes this one, opens a new pending proposal from the responder
    if p_counter_date is null or p_counter_start is null or p_counter_end is null then
      raise exception 'a counter needs a date, start time, and end time';
    end if;
    update public.call_proposals set status = 'countered', responded_at = now() where id = p_proposal_id;
    v_new := public.propose_call(v_prop.engagement_id, p_counter_date, p_counter_start, p_counter_end);
    -- propose_call's own "supersede pending" step already closed nothing
    -- (this one is now 'countered', not 'pending'), and it correctly stamps
    -- proposed_by as the CALLER (the responder), not the original proposer.
    update public.call_proposals set parent_proposal_id = p_proposal_id where id = v_new.id;
    return v_new;
  end if;

  select * into v_new from public.call_proposals where id = p_proposal_id;
  return v_new;
end;
$$;

revoke execute on function public.propose_call(uuid,date,time,time) from public;
grant  execute on function public.propose_call(uuid,date,time,time) to authenticated;
revoke execute on function public.respond_to_call_proposal(uuid,text,date,time,time) from public;
grant  execute on function public.respond_to_call_proposal(uuid,text,date,time,time) to authenticated;

select proname from pg_proc where proname in ('propose_call','respond_to_call_proposal');
