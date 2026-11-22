-- HU (owner, 2026-11-22): a trainee can reply to a coach's review (and the coach can answer). Replies hang off the review,
-- both parties read them, and they are written only through reply_to_review(), which also notifies the other side
-- (push to the review, guarded - rule 7/8). Safe to re-run.
create table if not exists public.review_replies (
  id         uuid primary key default gen_random_uuid(),
  review_id  uuid not null references public.reviews(id) on delete cascade,
  author_id  uuid not null references auth.users(id) on delete cascade,
  body       text not null check (length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index if not exists review_replies_review_idx on public.review_replies (review_id, created_at);
alter table public.review_replies enable row level security;
drop policy if exists "parties read review replies" on public.review_replies;
create policy "parties read review replies" on public.review_replies for select using (
  exists (select 1 from public.reviews r join public.submissions s on s.id = r.submission_id
           where r.id = review_replies.review_id and (r.coach_id = auth.uid() or s.trainee_id = auth.uid())));
revoke all on public.review_replies from anon, authenticated;
grant select on public.review_replies to authenticated;

create or replace function public.reply_to_review(p_review uuid, p_body text) returns uuid
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); v_coach uuid; v_trainee uuid; v_assigned uuid; v_withdrawn timestamptz; v_id uuid; v_to uuid; v_name text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_body is null or length(btrim(p_body)) = 0 then raise exception 'Write a reply first'; end if;
  select r.coach_id, s.trainee_id, s.assigned_id, r.withdrawn_at into v_coach, v_trainee, v_assigned, v_withdrawn
    from public.reviews r join public.submissions s on s.id = r.submission_id where r.id = p_review;
  if v_coach is null then raise exception 'review not found'; end if;
  if uid <> v_coach and uid <> v_trainee then raise exception 'not your review'; end if;
  if v_withdrawn is not null then raise exception 'This review was withdrawn'; end if;
  insert into public.review_replies (review_id, author_id, body) values (p_review, uid, left(btrim(p_body), 2000)) returning id into v_id;
  v_to := case when uid = v_coach then v_trainee else v_coach end;
  if to_regclass('public.push_outbox') is not null then
    begin
      select display_name into v_name from public.profiles where id = uid;
      insert into public.push_outbox (to_user, kind, title, body, url)
      values (v_to, 'review', '💬 ' || coalesce(v_name, 'Reply') || ' replied to the review', left(btrim(p_body), 120), '/#review=' || v_assigned);
    exception when others then raise warning 'review reply push skipped: %', sqlerrm; end;
  end if;
  return v_id;
end $$;
revoke execute on function public.reply_to_review(uuid, text) from public, anon, authenticated;
grant  execute on function public.reply_to_review(uuid, text) to authenticated;

-- Check: expect  table 1 | rls true | callable true
select
  (select count(*) from information_schema.tables where table_schema = 'public' and table_name = 'review_replies') as "table",
  (select relrowsecurity from pg_class where relname = 'review_replies') as rls,
  has_function_privilege('authenticated', 'public.reply_to_review(uuid,text)', 'execute') as callable;
