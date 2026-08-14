-- =====================================================================
-- FormTrace — item O: admin coach inactivity / missed-review monitoring
-- Run in the Supabase SQL editor. Requires migrations_payment_ledger_v2.sql.
--
-- THE SIGNAL: for a finalized cycle (status <> 'pending', meaning its
-- payment date has passed and the numbers are final), agreed_count is what
-- was committed for the week, reviewed_count is what the coach actually
-- graded, and missed_count is what the TRAINEE never submitted at all.
-- Neither of those alone is a clean "coach is negligent" signal —
-- reviewed_count is low whether the coach didn't review OR the trainee
-- didn't show up, and that's the trainee's fault, not the coach's.
--
--     unreviewed = agreed_count - reviewed_count - missed_count
--
-- is the part that's genuinely on the coach: the trainee DID submit, and
-- nobody ever graded it.
--
-- DECIDED: this returns a raw sorted signal (unreviewed count per coach
-- over their last N finalized cycles), not an opaque auto-"flagged"
-- boolean. Inventing a numeric threshold for what counts as "routine"
-- wasn't asked for and isn't obviously right at any specific number — an
-- admin looking at a sorted list can judge severity themselves. If a hard
-- threshold is wanted later, it's a small addition on top of this, not a
-- redesign.
-- =====================================================================

create or replace function public.admin_coach_inactivity(p_lookback_cycles integer default 8)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  out jsonb;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and is_admin) then
    raise exception 'not authorised';
  end if;

  select coalesce(jsonb_agg(row order by total_unreviewed desc, unreviewed_rate desc), '[]'::jsonb)
  into out
  from (
    with recent_weeks as (
      -- the coach's N most recent distinct calendar weeks with any
      -- finalized cycle, regardless of how many trainees generated them
      select coach_id, cycle_start,
             dense_rank() over (partition by coach_id order by cycle_start desc) as wk_rank
      from (
        select distinct e.coach_id, pc.cycle_start
        from public.payment_cycles pc
        join public.engagements e on e.id = pc.engagement_id
        where pc.status <> 'pending'
      ) weeks
    ),
    agg as (
      select e.coach_id,
             count(*)                                   as cycles_considered,
             sum(pc.agreed_count)                        as total_agreed,
             sum(pc.reviewed_count)                       as total_reviewed,
             sum(pc.missed_count)                         as total_missed,
             max(pc.cycle_start)                          as most_recent_cycle_start
      from public.payment_cycles pc
      join public.engagements e on e.id = pc.engagement_id
      join recent_weeks rw on rw.coach_id = e.coach_id and rw.cycle_start = pc.cycle_start
      where pc.status <> 'pending' and rw.wk_rank <= p_lookback_cycles
      group by e.coach_id
    )
    select jsonb_build_object(
      'coach_id', a.coach_id,
      'display_name', p.display_name,
      'cycles_considered', a.cycles_considered,
      'total_agreed', a.total_agreed,
      'total_reviewed', a.total_reviewed,
      'total_missed', a.total_missed,
      'total_unreviewed', greatest(0, a.total_agreed - a.total_reviewed - a.total_missed),
      'unreviewed_rate', case when a.total_agreed > 0
        then round(greatest(0, a.total_agreed - a.total_reviewed - a.total_missed)::numeric / a.total_agreed * 100, 1)
        else 0 end,
      'most_recent_cycle_start', a.most_recent_cycle_start
    ) as row,
    greatest(0, a.total_agreed - a.total_reviewed - a.total_missed) as total_unreviewed,
    case when a.total_agreed > 0
      then greatest(0, a.total_agreed - a.total_reviewed - a.total_missed)::numeric / a.total_agreed
      else 0 end as unreviewed_rate
    from agg a
    join public.profiles p on p.id = a.coach_id
  ) s;

  return out;
end;
$$;

revoke execute on function public.admin_coach_inactivity(integer) from public;
grant  execute on function public.admin_coach_inactivity(integer) to authenticated;

select proname from pg_proc where proname = 'admin_coach_inactivity';
