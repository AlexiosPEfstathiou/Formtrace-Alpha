-- =====================================================================
-- FormTrace — coach sees when a trainee declined their offer
-- Run in the Supabase SQL editor.
--
-- WHY
--   The market screen only ever showed a resolved offer's outcome once its
--   LISTING left the open pool, so a decline on a listing with other
--   offers still pending — or before the trainee had decided at all — was
--   invisible: it stayed tagged "✓ Pitched" with no outcome ever surfacing.
--   That is fixed client-side by splitting on the offer's own status.
--
--   This migration adds the acknowledgement column so the homepage notice
--   can be dismissed once seen, the same pattern as postpone_seen_at.
-- =====================================================================

alter table public.offers
  add column if not exists coach_seen_at timestamptz;

create index if not exists offers_coach_unseen_idx
  on public.offers (coach_id, status)
  where status in ('rejected','expired') and coach_seen_at is null;
