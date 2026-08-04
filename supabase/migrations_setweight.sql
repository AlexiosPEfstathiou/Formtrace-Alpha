-- =====================================================================
-- FormTrace — weight used per set
-- Run this in the Supabase SQL editor.
--
-- Load is recorded per set on set_labels (not inside the submission JSON)
-- so the coach's review can look up what the trainee lifted for the same
-- exercise on a previous day with a plain indexed query.
-- =====================================================================

alter table public.set_labels
  add column if not exists weight_kg numeric;

-- supports "most recent previous weight for this trainee + exercise"
create index if not exists set_labels_hist_idx
  on public.set_labels (trainee_id, exercise_name, created_at desc);
