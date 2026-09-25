-- CN-11: card dismissals stored server-side (localStorage was not reliable on the installed app).
create table if not exists public.dismissals (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  key          text not null,
  dismissed_at timestamptz not null default now(),
  primary key (user_id, key)
);
alter table public.dismissals enable row level security;
drop policy if exists "own dismissals" on public.dismissals;
create policy "own dismissals" on public.dismissals for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
select 'dismissals' as check, count(*) from information_schema.tables where table_schema='public' and table_name='dismissals';