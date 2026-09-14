-- =====================================================================
-- FormTrace — Item AY part 2: a meeting link on accepted calls.
-- Run in the Supabase SQL editor.
-- Decided 2026-09-14: Google Meet. Minting a link programmatically needs
-- Google OAuth + a server, neither of which exists yet; so either party
-- pastes a Meet link (Google's meet.google.com/new mints an instant room).
-- One link per proposal row - a recurring series shares it.
-- =====================================================================
alter table public.call_proposals add column if not exists meeting_url text;

create or replace function public.set_call_meeting_url(p_proposal_id uuid, p_url text)
returns public.call_proposals
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  v_prop record;
  v_eng record;
  v_url text := nullif(trim(p_url), '');
  v_row public.call_proposals;
begin
  select * into v_prop from public.call_proposals where id = p_proposal_id;
  if not found then raise exception 'call not found'; end if;
  select coach_id, trainee_id into v_eng from public.engagements where id = v_prop.engagement_id;
  if uid <> v_eng.coach_id and uid <> v_eng.trainee_id then raise exception 'not a party to this engagement'; end if;
  if v_prop.status <> 'accepted' then raise exception 'the call has to be accepted first'; end if;
  if v_url is not null and v_url !~* '^https://' then raise exception 'the link must start with https://'; end if;
  update public.call_proposals set meeting_url = v_url where id = p_proposal_id returning * into v_row;
  return v_row;
end;
$$;
revoke execute on function public.set_call_meeting_url(uuid, text) from public;
grant  execute on function public.set_call_meeting_url(uuid, text) to authenticated;

select 'meeting_url column' as check, count(*) from information_schema.columns
 where table_schema='public' and table_name='call_proposals' and column_name='meeting_url';
