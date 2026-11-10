-- Item GF (security review 2026-11-10): what a social handle may contain.
-- Handles are shown to connections and turned into links. The app now encodes them, and this adds the database rule:
-- letters, digits and the few characters real handles use - nothing that could break out of a link or a tag.
-- NOT VALID = the rule applies to every new or changed value but does not reject rows that are already there
-- (the check below counts those, so they can be corrected by hand). Safe to re-run.
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_whatsapp_safe') then
    alter table public.profiles add constraint profiles_whatsapp_safe
      check (whatsapp is null or whatsapp = '' or whatsapp ~ '^[+0-9 ()./-]{4,30}$') not valid; end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_instagram_safe') then
    alter table public.profiles add constraint profiles_instagram_safe
      check (instagram is null or instagram = '' or instagram ~ '^@?[A-Za-z0-9._-]{1,60}$') not valid; end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_snapchat_safe') then
    alter table public.profiles add constraint profiles_snapchat_safe
      check (snapchat is null or snapchat = '' or snapchat ~ '^@?[A-Za-z0-9._-]{1,60}$') not valid; end if;
  if not exists (select 1 from pg_constraint where conname = 'handle_shares_handle_safe') then
    alter table public.handle_shares add constraint handle_shares_handle_safe
      check (handle is null or handle = '' or handle ~ '^[A-Za-z0-9@+ ()./_-]{1,60}$') not valid; end if;
end $$;

-- Check: expect  rules = 4.  The other two numbers are existing values the rule would refuse (0 is ideal; if not,
-- tell Claude - they were written before the rule and can be corrected).
select (select count(*) from pg_constraint where conname in ('profiles_whatsapp_safe','profiles_instagram_safe','profiles_snapchat_safe','handle_shares_handle_safe')) as rules,
       (select count(*) from public.profiles
         where (coalesce(whatsapp,'')  <> '' and whatsapp  !~ '^[+0-9 ()./-]{4,30}$')
            or (coalesce(instagram,'') <> '' and instagram !~ '^@?[A-Za-z0-9._-]{1,60}$')
            or (coalesce(snapchat,'')  <> '' and snapchat  !~ '^@?[A-Za-z0-9._-]{1,60}$')) as profiles_to_correct,
       (select count(*) from public.handle_shares
         where coalesce(handle,'') <> '' and handle !~ '^[A-Za-z0-9@+ ()./_-]{1,60}$') as shares_to_correct;