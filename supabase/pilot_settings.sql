-- =====================================================================
-- FormTrace — DK: pilot settings. Run when the pilot starts.
-- During the pilot trainees pay coaches directly, so nothing is collected;
-- these zeros make the app SHOW what really happens.
-- =====================================================================
-- keep the launch values so they can be restored exactly
insert into public.platform_rates (key, value, note)
select 'launch_' || key, value, 'saved before the pilot: ' || coalesce(note,'') from public.platform_rates
 where key in ('trainee_fee_pct','trainee_fee_min','coach_commission_pct')
on conflict (key) do nothing;

update public.platform_rates set value = 0 where key in ('trainee_fee_pct','trainee_fee_min','coach_commission_pct');

-- Founding coaches (0% commission forever, BQ): grant by sign-in email once they have signed up
update public.profiles p set founding_at = coalesce(p.founding_at, now())
  from auth.users u
 where u.id = p.id
   and lower(u.email) in (lower('coach1@example.com'), lower('coach2@example.com'));   -- <- the pilot coaches' emails

select key, value from public.platform_rates where key not like 'launch_%' order by key;
select p.display_name, u.email, p.founding_at from public.profiles p join auth.users u on u.id = p.id where p.founding_at is not null;

-- ---------------------------------------------------------------------
-- AFTER the pilot, when Stripe (BI) is live - restore the launch rates:
-- update public.platform_rates r set value = l.value
--   from public.platform_rates l where l.key = 'launch_' || r.key
--    and r.key in ('trainee_fee_pct','trainee_fee_min','coach_commission_pct');
-- ---------------------------------------------------------------------