-- =====================================================================
-- FormTrace — sync appearance settings to the account, not just the device
-- Run in the Supabase SQL editor.
--
-- Theme and colourblind mode were both stored ONLY in localStorage, so
-- setting either on one device did nothing on another — reported for
-- colourblind mode specifically, but theme has the identical gap and
-- fixing only one would leave the same settings screen half-synced.
--
-- localStorage stays as the fast, no-network first-paint source (see the
-- inline script before the app boots) — this adds the account as the
-- SOURCE OF TRUTH that a new device pulls from once signed in.
-- =====================================================================

alter table public.profiles
  add column if not exists colorblind_mode boolean not null default false,
  add column if not exists theme_pref      text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname='profiles_theme_pref_chk') then
    alter table public.profiles add constraint profiles_theme_pref_chk
      check (theme_pref is null or theme_pref in ('light','dark','system'));
  end if;
end $$;

-- these two join the existing set a client may write to its own row
grant update (colorblind_mode, theme_pref) on public.profiles to authenticated;

select count(*) filter (where colorblind_mode) as cb_users, count(*) as total from public.profiles;
