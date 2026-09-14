-- FormTrace — certification review notice on the coach homepage (dismissable)
alter table public.coach_certifications add column if not exists seen_at timestamptz;
select 'seen_at' as check, count(*) from information_schema.columns where table_schema='public' and table_name='coach_certifications' and column_name='seen_at';
