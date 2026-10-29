-- DL: a trainee who cannot pay yet asks the coach for payment details (push). Run after migrations_payment_tracker.sql.
create or replace function public.request_payout_details(p_eng uuid)
returns public.engagements language plpgsql security definer set search_path = public as $$
declare e public.engagements;
begin
  select * into e from public.engagements where id = p_eng and trainee_id = auth.uid();
  if not found then raise exception 'not your goal'; end if;
  perform public._pay_push(e.coach_id, '💶 ' || public._name_of(e.trainee_id) || ' is ready to pay you',
    'Add how trainees pay you - open their goal and tap "Add how trainees pay you"', '/#coach');
  return e;
end; $$;
revoke execute on function public.request_payout_details(uuid) from public;
grant  execute on function public.request_payout_details(uuid) to authenticated;