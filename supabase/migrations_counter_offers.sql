-- =====================================================================
-- FormTrace — Item CJ: trainee counter-offers.
-- Run in the Supabase SQL editor.
-- A small disagreement should not end a match. On a pending offer the
-- trainee may propose a change to weeks / sessions per week / weekly price
-- with a note; the offer goes to 'countered'. The coach either ACCEPTS the
-- change (terms are rewritten, offer returns to 'pending' for the trainee
-- to accept) or KEEPS the original terms (returns to 'pending' unchanged,
-- with the coach's note). One counter at a time; a second counter replaces
-- the first.
-- =====================================================================
alter table public.offers drop constraint if exists offers_status_check;
alter table public.offers add constraint offers_status_check
  check (status in ('pending','accepted','rejected','expired','countered'));

alter table public.offers
  add column if not exists counter_length_weeks integer,
  add column if not exists counter_sessions     integer,
  add column if not exists counter_weekly_cents integer,
  add column if not exists counter_note         text,
  add column if not exists counter_at           timestamptz,
  add column if not exists counter_outcome      text check (counter_outcome is null or counter_outcome in ('accepted','kept')),
  add column if not exists counter_reply        text,
  add column if not exists counter_resolved_at  timestamptz;

create or replace function public.counter_offer(
  p_offer uuid, p_weeks integer, p_sessions integer, p_weekly_cents integer, p_note text default null
)
returns public.offers
language plpgsql
security definer
set search_path = public
as $$
declare v public.offers;
begin
  select * into v from public.offers where id = p_offer;
  if not found then raise exception 'offer not found'; end if;
  if v.trainee_id <> auth.uid() then raise exception 'not your offer'; end if;
  if v.status not in ('pending','countered') then raise exception 'this offer is no longer open'; end if;
  if p_weeks is null or p_weeks < 1 or p_weeks > 104 then raise exception 'weeks must be 1-104'; end if;
  if p_sessions is null or p_sessions < 1 or p_sessions > 14 then raise exception 'sessions per week must be 1-14'; end if;
  if p_weekly_cents is null or p_weekly_cents < 0 then raise exception 'price must be 0 or more'; end if;
  update public.offers
     set status = 'countered',
         counter_length_weeks = p_weeks, counter_sessions = p_sessions, counter_weekly_cents = p_weekly_cents,
         counter_note = nullif(trim(coalesce(p_note,'')),''), counter_at = now(),
         counter_outcome = null, counter_reply = null, counter_resolved_at = null
   where id = p_offer returning * into v;
  return v;
end;
$$;
revoke execute on function public.counter_offer(uuid, integer, integer, integer, text) from public;
grant  execute on function public.counter_offer(uuid, integer, integer, integer, text) to authenticated;

create or replace function public.respond_counter(p_offer uuid, p_accept boolean, p_reply text default null)
returns public.offers
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.offers;
  v_cur text;
begin
  select * into v from public.offers where id = p_offer;
  if not found then raise exception 'offer not found'; end if;
  if v.coach_id <> auth.uid() then raise exception 'not your offer'; end if;
  if v.status <> 'countered' then raise exception 'nothing to respond to'; end if;
  v_cur := coalesce(substring(v.price_text from '^[^0-9 ]+'), '$');
  if p_accept then
    update public.offers
       set length_weeks = v.counter_length_weeks,
           length_text  = v.counter_length_weeks || ' week' || case when v.counter_length_weeks = 1 then '' else 's' end,
           workouts_per_week_cap = v.counter_sessions,
           sessions_text = v.counter_sessions || ' / week',
           rate_per_workout_cents = v.counter_weekly_cents,
           price_text = v_cur || trim(to_char(v.counter_weekly_cents / 100.0, 'FM999999990.##')) || ' / week',
           status = 'pending', counter_outcome = 'accepted',
           counter_reply = nullif(trim(coalesce(p_reply,'')),''), counter_resolved_at = now()
     where id = p_offer returning * into v;
  else
    update public.offers
       set status = 'pending', counter_outcome = 'kept',
           counter_reply = nullif(trim(coalesce(p_reply,'')),''), counter_resolved_at = now()
     where id = p_offer returning * into v;
  end if;
  return v;
end;
$$;
revoke execute on function public.respond_counter(uuid, boolean, text) from public;
grant  execute on function public.respond_counter(uuid, boolean, text) to authenticated;

select 'counter columns' as check, count(*) from information_schema.columns
 where table_schema='public' and table_name='offers' and column_name like 'counter_%';
