-- Item FV (owner, 2026-11-04): the name is Formtrace, not FormTrace - in everything users see.
-- 1) Every public function whose code contains "FormTrace" (push titles and bodies, the evidence pack, notes) is
--    re-created from its LIVE definition with the new spelling - nothing else in it changes. Extension functions skipped.
-- 2) A read-only report of stored data that still contains "FormTrace" (to review before changing any data).
-- Safe to re-run.
do $$
declare r record; def text; n int := 0;
begin
  for r in
    select p.oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.prokind in ('f','p') and p.prosrc like '%FormTrace%'
       and not exists (select 1 from pg_depend dp where dp.objid = p.oid and dp.deptype = 'e')
  loop
    def := pg_get_functiondef(r.oid);
    execute replace(def, 'FormTrace', 'Formtrace');
    n := n + 1;
  end loop;
  raise notice 'functions re-created: %', n;
end $$;

-- 2) where stored data still says FormTrace (report only)
create temp table if not exists _fv_report (table_name text, column_name text, rows_with_old_name bigint);
truncate _fv_report;
do $$
declare r record; c bigint;
begin
  for r in select table_name, column_name from information_schema.columns c
            join information_schema.tables t using (table_schema, table_name)
           where c.table_schema = 'public' and t.table_type = 'BASE TABLE' and c.data_type in ('text','character varying')
  loop
    execute format('select count(*) from public.%I where %I like %L', r.table_name, r.column_name, '%FormTrace%') into c;
    if c > 0 then insert into _fv_report values (r.table_name, r.column_name, c); end if;
  end loop;
end $$;

-- Check: expect  functions_left = 0 ; then the data report (may be empty)
select (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
         where ns.nspname = 'public' and p.prosrc like '%FormTrace%') as functions_left;
select * from _fv_report order by rows_with_old_name desc;