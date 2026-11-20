-- GW (2026-11-20): the 08:00 morning summary never reached a trainee. compose_daily_digest failed with
-- 'column reference "kcal" is ambiguous' (a variable named kcal and logs.kcal in the same query), the error rolled back
-- send_daily_digests for everyone, so nothing was sent and nothing was logged - every morning since it was built.
-- Fix: qualify the logs columns; and send_daily_digests now catches each person's error on its own, so one bad
-- summary can never stop the others again (CLAUDE.md rule 7). Safe to re-run.

do $$
declare src text;
begin
  src := pg_get_functiondef('public.compose_daily_digest(uuid, date)'::regprocedure);
  if position('from public.logs where trainee_id = p_user and log_date = p_day - 1 and (kcal is not null or protein_g is not null)' in src) > 0 then
    src := replace(src,
      'from public.logs where trainee_id = p_user and log_date = p_day - 1 and (kcal is not null or protein_g is not null)',
      'from public.logs lg where lg.trainee_id = p_user and lg.log_date = p_day - 1 and (lg.kcal is not null or lg.protein_g is not null)');
    src := replace(src,
      'from public.logs where trainee_id = p_user and log_date = p_day and weight_kg is not null',
      'from public.logs lg where lg.trainee_id = p_user and lg.log_date = p_day and lg.weight_kg is not null');
    execute src;
  end if;
end $$;

create or replace function public.send_daily_digests() returns integer
language plpgsql security definer set search_path = public as $$
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
    begin
      insert into public.daily_digest_log (user_id, local_date) values (u.id, u.local_day) on conflict do nothing;
      if not found then continue; end if;
      select * into d from public.compose_daily_digest(u.id, u.local_day);
      insert into public.push_outbox (to_user, kind, title, body, url) values (u.id, 'daily', d.title, d.body, d.url);
      n := n + 1;
    exception when others then
      raise warning 'daily digest for % skipped: %', u.id, sqlerrm;   -- one person's error never stops the others
    end;
  end loop;
  return n;
end $$;
revoke execute on function public.send_daily_digests() from public, anon, authenticated;

-- Check: expect  fixed 1 | per_person_guard 1 | composes 1
select
  (select count(*) from pg_proc where proname = 'compose_daily_digest' and prosrc like '%lg.kcal is not null%') as fixed,
  (select count(*) from pg_proc where proname = 'send_daily_digests' and prosrc like '%skipped%') as per_person_guard,
  (select count(*) from public.compose_daily_digest((select id from public.profiles where tz is not null and role is distinct from 'coach' limit 1), current_date)) as composes;
