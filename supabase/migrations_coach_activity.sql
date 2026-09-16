-- =====================================================================
-- FormTrace — Item CD (remainder): coach scan activity stamp.
-- Run in the Supabase SQL editor.
-- last_market_at is set by the app whenever a coach opens Open goals; the
-- admin screen reads it with the pitch counts to see who is keeping the
-- daily-scan promise (launch timeline phase 3).
-- =====================================================================
alter table public.profiles add column if not exists last_market_at timestamptz;

create or replace function public.admin_coach_activity()
returns table (coach_id uuid, display_name text, last_market_at timestamptz, pitches_7d integer, pitches_30d integer, open_goals_unpitched integer)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.last_market_at,
         (select count(*)::int from public.offers o where o.coach_id = p.id and o.created_at > now() - interval '7 days'),
         (select count(*)::int from public.offers o where o.coach_id = p.id and o.created_at > now() - interval '30 days'),
         (select count(*)::int from public.listings l where l.status = 'open'
            and not exists (select 1 from public.offers o where o.listing_id = l.id and o.coach_id = p.id)
            and not exists (select 1 from public.listing_hides h where h.listing_id = l.id and h.coach_id = p.id))
    from public.profiles p
   where p.role = 'coach'
     and exists (select 1 from public.profiles a where a.id = auth.uid() and a.is_admin)
   order by p.last_market_at desc nulls last;
$$;
revoke execute on function public.admin_coach_activity() from public;
grant  execute on function public.admin_coach_activity() to authenticated;

select 'last_market_at' as check, count(*) from information_schema.columns
 where table_schema='public' and table_name='profiles' and column_name='last_market_at';
