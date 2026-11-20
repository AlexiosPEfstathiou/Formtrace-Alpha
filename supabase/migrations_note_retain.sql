-- HG (owner, 2026-11-20): a coach's set note can be kept only on that set. The review entry gets "retain": false when the
-- coach unticks "Retain note when trainee performs this exercise again"; exercise_notes() (the per-exercise note history the
-- trainee sees every time) then leaves that comment out. Notes without the flag (all older ones) stay in the history.
-- The voice-over replay is not affected. Safe to re-run.
do $$
declare src text;
begin
  src := pg_get_functiondef('public.exercise_notes(uuid, uuid[], text[])'::regprocedure);
  if position('y.e->>''retain''' in src) = 0 then
    src := replace(src, 'nullif(btrim(y.e->>''comment''), '''')',
                   '(case when y.e->>''retain'' = ''false'' then null else nullif(btrim(y.e->>''comment''), '''') end)');
    execute src;
  end if;
end $$;

-- Check: expect  retain_filter 1
select count(*) as retain_filter from pg_proc where proname = 'exercise_notes' and prosrc like '%y.e->>''retain'' = ''false''%';
