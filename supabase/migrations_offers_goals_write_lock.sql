-- Item GG (security review 2026-11-10): offers and goals - only the app's own fields can be written.
-- Before: either party could update ANY column of an offer (including the price the checkout charges from) and insert,
-- update or delete a goal on EVERY column (only the deposit columns were guarded, and only on update).
-- Now, for signed-in users writing directly from the app:
--   offers       insert: the 17 fields a coach's offer consists of      update: status, viewed_at, coach_seen_at   delete: no
--   engagements  insert: the 7 fields the app sets on acceptance         update: status, completed_at, outcome,
--                                                                                billing_active, level              delete: no
-- plus two guards for what columns cannot express (see the functions below).
-- Database functions (counter-offers, paid / received stamps, ending a goal, account deletion...) and the service role
-- (Stripe webhook, checkout) are unaffected: they run with the owner's rights. Reading is unchanged.
-- Column names are read from the live tables; a wanted column that does not exist is skipped and listed by the check.
-- Safe to re-run.

do $$
declare
  w_off_ins text[] := array['listing_id','coach_id','trainee_id','kind','title','focus','length_text','start_text','sessions_text',
                            'price_text','pitch_video_path','status','rate_per_workout_cents','workouts_per_week_cap','length_weeks',
                            'start_date','noshow_fraction_pct'];
  w_off_upd text[] := array['status','viewed_at','coach_seen_at'];
  w_eng_ins text[] := array['offer_id','coach_id','trainee_id','goal_title','status','committed_weeks','committed_end_date'];
  w_eng_upd text[] := array['status','completed_at','outcome','billing_active','level'];
  cols text;
begin
  revoke insert, update, delete, truncate on public.offers      from anon, authenticated;
  revoke insert, update, delete, truncate on public.engagements from anon, authenticated;

  select string_agg(quote_ident(column_name), ', ') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'offers' and column_name = any(w_off_ins);
  execute format('grant insert (%s) on public.offers to authenticated', cols);
  select string_agg(quote_ident(column_name), ', ') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'offers' and column_name = any(w_off_upd);
  execute format('grant update (%s) on public.offers to authenticated', cols);

  select string_agg(quote_ident(column_name), ', ') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'engagements' and column_name = any(w_eng_ins);
  execute format('grant insert (%s) on public.engagements to authenticated', cols);
  select string_agg(quote_ident(column_name), ', ') into cols from information_schema.columns
   where table_schema = 'public' and table_name = 'engagements' and column_name = any(w_eng_upd);
  execute format('grant update (%s) on public.engagements to authenticated', cols);
end $$;

-- Guard 1: offers. Not security definer on purpose: current_user is then the real caller, so writes made by database
-- functions (owner) and by the service role pass through, and only direct writes from the app are checked.
create or replace function public._guard_offer_client_write() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if tg_op = 'INSERT' then
    if new.status is distinct from 'pending' then raise exception 'A new offer starts as pending.'; end if;
    return new;
  end if;
  if new.status is distinct from old.status then
    if old.status = 'accepted' then raise exception 'An accepted offer cannot be changed.'; end if;
    if new.status = 'accepted' then
      if auth.uid() is distinct from old.trainee_id then raise exception 'Only the trainee can accept an offer.'; end if;
      if old.status <> 'pending' then raise exception 'Only a pending offer can be accepted.'; end if;
    elsif new.status <> 'rejected' then
      raise exception 'That change to an offer is not allowed.';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists guard_offer_client_write on public.offers;
create trigger guard_offer_client_write before insert or update on public.offers
  for each row execute function public._guard_offer_client_write();

-- Guard 2: goals. A new goal must come from an accepted offer: same coach and trainee, created by the trainee who
-- accepted it, one goal per offer; it starts active and takes its length from the offer.
create or replace function public._guard_engagement_client_write() returns trigger
language plpgsql set search_path = public as $$
declare o record;
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if tg_op = 'INSERT' then
    if new.offer_id is null then raise exception 'A goal starts from an accepted offer.'; end if;
    select id, coach_id, trainee_id, status, length_weeks into o from public.offers where id = new.offer_id;
    if not found or o.status <> 'accepted' then raise exception 'A goal starts from an accepted offer.'; end if;
    if auth.uid() is distinct from o.trainee_id or new.trainee_id is distinct from o.trainee_id
       or new.coach_id is distinct from o.coach_id then raise exception 'This goal does not match its offer.'; end if;
    if exists (select 1 from public.engagements e where e.offer_id = new.offer_id) then
      raise exception 'This offer already has a goal.'; end if;
    new.status := 'active';
    if o.length_weeks is not null then new.committed_weeks := o.length_weeks; end if;
    return new;
  end if;
  if new.status is distinct from old.status and new.status not in ('active', 'completed', 'ended') then
    raise exception 'That goal status is not allowed.'; end if;
  return new;
end $$;
drop trigger if exists guard_engagement_client_write on public.engagements;
create trigger guard_engagement_client_write before insert or update on public.engagements
  for each row execute function public._guard_engagement_client_write();

-- Check: expect  offers_insert 17 | offers_update 3 | goals_insert 7 | goals_update 5 | table_level_writes 0 | guards 2 | missing empty
with want(tbl, priv, col) as (
  select 'offers', 'INSERT', unnest(array['listing_id','coach_id','trainee_id','kind','title','focus','length_text','start_text','sessions_text','price_text','pitch_video_path','status','rate_per_workout_cents','workouts_per_week_cap','length_weeks','start_date','noshow_fraction_pct'])
  union all select 'offers', 'UPDATE', unnest(array['status','viewed_at','coach_seen_at'])
  union all select 'engagements', 'INSERT', unnest(array['offer_id','coach_id','trainee_id','goal_title','status','committed_weeks','committed_end_date'])
  union all select 'engagements', 'UPDATE', unnest(array['status','completed_at','outcome','billing_active','level'])
), have as (
  select table_name as tbl, privilege_type as priv, column_name as col from information_schema.column_privileges
   where table_schema = 'public' and table_name in ('offers','engagements') and grantee = 'authenticated'
     and privilege_type in ('INSERT','UPDATE')
)
select (select count(*) from have where tbl = 'offers' and priv = 'INSERT')       as offers_insert,
       (select count(*) from have where tbl = 'offers' and priv = 'UPDATE')       as offers_update,
       (select count(*) from have where tbl = 'engagements' and priv = 'INSERT')  as goals_insert,
       (select count(*) from have where tbl = 'engagements' and priv = 'UPDATE')  as goals_update,
       (select count(*) from information_schema.table_privileges where table_schema = 'public'
          and table_name in ('offers','engagements') and grantee in ('anon','authenticated')
          and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE'))            as table_level_writes,
       (select count(*) from pg_trigger where tgname in ('guard_offer_client_write','guard_engagement_client_write') and not tgisinternal) as guards,
       (select coalesce(string_agg(w.tbl || '.' || w.col || ' (' || lower(w.priv) || ')', ', '), '')
          from want w where not exists (select 1 from have h where h.tbl = w.tbl and h.priv = w.priv and h.col = w.col)) as missing;
