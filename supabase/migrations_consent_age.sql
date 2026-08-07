-- =====================================================================
-- FormTrace — age gate and recorded consent
-- Run in the Supabase SQL editor.
--
-- The app stores body photos, body measurements, weight and food intake.
-- That is health-adjacent and, under UK GDPR, arguably special-category
-- data. Two things were missing: any record that the user agreed to it,
-- and any check that they are old enough to agree at all.
--
-- consent_version is stored, not just a boolean, so that changing the
-- privacy notice can re-prompt existing users instead of silently
-- relying on consent given to an older document.
-- =====================================================================

alter table public.profiles
  add column if not exists date_of_birth   date,
  add column if not exists consent_version text,
  add column if not exists consented_at    timestamptz;

-- Age is checked in the client before this is written, but a constraint
-- makes an under-18 row impossible even via the API. 18 rather than 16
-- because the app collects full-body progress photos.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_min_age_chk') then
    alter table public.profiles
      add constraint profiles_min_age_chk
      check (date_of_birth is null or date_of_birth <= (current_date - interval '18 years'));
  end if;
end $$;

-- lets you answer "who has not consented to the current notice?"
create index if not exists profiles_consent_idx
  on public.profiles (consent_version);

select count(*) filter (where consented_at is null) as awaiting_consent,
       count(*)                                      as total_profiles
from public.profiles;
