-- =====================================================================
-- FormTrace — Item DL (pilot): payment tracker. Pilot money goes directly to the
-- coach; the escrow step is shown as skipped until Stripe (BI). Run in the SQL editor.
-- =====================================================================

-- 1. how trainees pay a coach - NOT on profiles (profiles are broadly readable)
create table if not exists public.coach_payout_details (
  coach_id   uuid primary key references public.profiles(id) on delete cascade,
  details    text not null check (length(details) between 1 and 300),
  updated_at timestamptz not null default now()
);
alter table public.coach_payout_details enable row level security;
drop policy if exists "coach reads own payout details" on public.coach_payout_details;
create policy "coach reads own payout details" on public.coach_payout_details for select to authenticated using (coach_id = auth.uid());
drop policy if exists "their trainees read payout details" on public.coach_payout_details;
create policy "their trainees read payout details" on public.coach_payout_details for select to authenticated
  using (exists (select 1 from public.engagements e where e.coach_id = coach_payout_details.coach_id and e.trainee_id = auth.uid()));
create or replace function public.set_my_payout_details(p_details text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if nullif(trim(coalesce(p_details,'')),'') is null then delete from public.coach_payout_details where coach_id = auth.uid(); return; end if;
  insert into public.coach_payout_details (coach_id, details) values (auth.uid(), left(trim(p_details),300))
  on conflict (coach_id) do update set details = excluded.details, updated_at = now();
end; $$;
revoke execute on function public.set_my_payout_details(text) from public;
grant  execute on function public.set_my_payout_details(text) to authenticated;

-- 2. payment state on the goal
alter table public.engagements
  add column if not exists paid_at            timestamptz,
  add column if not exists paid_note          text,
  add column if not exists received_at        timestamptz,
  add column if not exists refund_sent_at     timestamptz,
  add column if not exists refund_received_at timestamptz;

-- 3. the four confirmations, each by the right party only; each tells the other side (push)
create or replace function public._pay_push(p_to uuid, p_title text, p_body text, p_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if to_regclass('public.push_outbox') is null then return; end if;
  begin insert into public.push_outbox (to_user, kind, title, body, url) values (p_to, 'offer', p_title, p_body, p_url);
  exception when others then raise warning 'payment push skipped: %', sqlerrm; end;
end; $$;

create or replace function public.mark_paid(p_eng uuid, p_note text default null)
returns public.engagements language plpgsql security definer set search_path = public as $$
declare e public.engagements;
begin
  update public.engagements set paid_at = coalesce(paid_at, now()), paid_note = nullif(left(coalesce(p_note,''),200),'')
   where id = p_eng and trainee_id = auth.uid() returning * into e;
  if not found then raise exception 'not your goal'; end if;
  perform public._pay_push(e.coach_id, '💶 ' || public._name_of(e.trainee_id) || ' says they paid you', coalesce(e.goal_title,'Goal') || ' · confirm when it arrives', '/#coach');
  return e;
end; $$;

create or replace function public.confirm_received(p_eng uuid)
returns public.engagements language plpgsql security definer set search_path = public as $$
declare e public.engagements;
begin
  update public.engagements set received_at = coalesce(received_at, now()), paid_at = coalesce(paid_at, now())
   where id = p_eng and coach_id = auth.uid() returning * into e;
  if not found then raise exception 'not your trainee'; end if;
  perform public._pay_push(e.trainee_id, '✓ ' || public._name_of(e.coach_id) || ' confirmed your payment', coalesce(e.goal_title,'Goal'), '/#listings');
  return e;
end; $$;

create or replace function public.mark_refund_sent(p_eng uuid)
returns public.engagements language plpgsql security definer set search_path = public as $$
declare e public.engagements;
begin
  update public.engagements set refund_sent_at = coalesce(refund_sent_at, now())
   where id = p_eng and coach_id = auth.uid() and status <> 'active' returning * into e;
  if not found then raise exception 'not an ended goal of yours'; end if;
  perform public._pay_push(e.trainee_id, '↩ ' || public._name_of(e.coach_id) || ' sent your refund', coalesce(e.goal_title,'Goal') || ' · confirm when it arrives', '/#listings');
  return e;
end; $$;

create or replace function public.confirm_refund_received(p_eng uuid)
returns public.engagements language plpgsql security definer set search_path = public as $$
declare e public.engagements;
begin
  update public.engagements set refund_received_at = coalesce(refund_received_at, now())
   where id = p_eng and trainee_id = auth.uid() returning * into e;
  if not found then raise exception 'not your goal'; end if;
  return e;
end; $$;

do $$ declare f text; begin
  foreach f in array array['mark_paid(uuid,text)','confirm_received(uuid)','mark_refund_sent(uuid)','confirm_refund_received(uuid)'] loop
    execute format('revoke execute on function public.%s from public', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

select 'payment tracker' as check,
  (select count(*) from information_schema.columns where table_schema='public' and table_name='engagements' and column_name in ('paid_at','received_at','refund_sent_at','refund_received_at')) as engagement_columns,
  (select count(*) from information_schema.tables where table_schema='public' and table_name='coach_payout_details') as payout_table;
