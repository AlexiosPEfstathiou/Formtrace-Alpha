-- CN-14: In Touch connections may read each other's profile row (name, photo, initials).
-- First trainee <-> trainee relationship in the app; earlier profile policies assumed coach <-> trainee.
drop policy if exists "in touch connections read profiles" on public.profiles;
create policy "in touch connections read profiles" on public.profiles
  for select to authenticated
  using (
    exists (
      select 1 from public.connections c
       where c.status in ('pending','confirmed')
         and ((c.a = auth.uid() and c.b = profiles.id) or (c.b = auth.uid() and c.a = profiles.id))
    )
  );
select 'policy added' as check;