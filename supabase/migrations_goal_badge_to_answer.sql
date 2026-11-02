-- =====================================================================
-- FormTrace — FJ: the trainee's Goal badge counts offers WAITING FOR AN ANSWER (pending),
-- not only pitches not yet seen. Adds 'to_answer' to my_tab_badges(); the rest unchanged.
-- =====================================================================
create or replace function public.my_tab_badges() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'unpitched', (select count(*) from public.listings l
                   where l.status = 'open' and l.trainee_id <> auth.uid()
                     and not exists (select 1 from public.listing_hides h where h.listing_id = l.id and h.coach_id = auth.uid())
                     and not exists (select 1 from public.offers o where o.listing_id = l.id and o.coach_id = auth.uid())),
    'unseen',    (select count(*) from public.offers o
                   where o.trainee_id = auth.uid() and o.status = 'pending' and o.seen_at is null),
    'to_answer', (select count(*) from public.offers o
                   where o.trainee_id = auth.uid() and o.status = 'pending')
  );
$$;
revoke execute on function public.my_tab_badges() from public;
grant  execute on function public.my_tab_badges() to authenticated;

select (public.my_tab_badges() ? 'to_answer') as has_to_answer;