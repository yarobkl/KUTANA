-- Notifications belong to the recipient. Only database triggers create them.
create table public.job_favorites (
 user_id uuid not null references auth.users(id) on delete cascade,
 job_id uuid not null references public.jobs(id) on delete cascade,
 created_at timestamptz not null default now(),
 primary key (user_id, job_id)
);
create table public.job_alerts (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 keyword text not null check (char_length(btrim(keyword)) between 2 and 80),
 city text not null default '' check (char_length(city) <= 80),
 created_at timestamptz not null default now(),
 unique (user_id, keyword, city)
);
create table public.notification_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 messages_enabled boolean not null default true,
 jobs_enabled boolean not null default true
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references auth.users(id) on delete cascade,
 kind text not null check (kind in ('message', 'job')),
 title text not null,
 body text not null,
 reference_id uuid not null,
 created_at timestamptz not null default now(),
 read_at timestamptz,
 unique (recipient_id, kind, reference_id)
);
create index notifications_recipient_idx on public.notifications(recipient_id, created_at desc);
create index job_alerts_user_idx on public.job_alerts(user_id);

alter table public.job_favorites enable row level security;
alter table public.job_alerts enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.notifications enable row level security;
create policy "own favorites read" on public.job_favorites for select to authenticated using (user_id = (select auth.uid()));
create policy "own favorites insert" on public.job_favorites for insert to authenticated with check (user_id = (select auth.uid()) and exists (select 1 from public.jobs where id = job_id and status = 'published'));
create policy "own favorites delete" on public.job_favorites for delete to authenticated using (user_id = (select auth.uid()));
create policy "own alerts read" on public.job_alerts for select to authenticated using (user_id = (select auth.uid()));
create policy "own alerts insert" on public.job_alerts for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own alerts delete" on public.job_alerts for delete to authenticated using (user_id = (select auth.uid()));
create policy "own preferences read" on public.notification_preferences for select to authenticated using (user_id = (select auth.uid()));
create policy "own preferences insert" on public.notification_preferences for insert to authenticated with check (user_id = (select auth.uid()));
create policy "own preferences update" on public.notification_preferences for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "own notifications read" on public.notifications for select to authenticated using (recipient_id = (select auth.uid()));
create policy "own notifications mark read" on public.notifications for update to authenticated using (recipient_id = (select auth.uid())) with check (recipient_id = (select auth.uid()));
revoke all on public.job_favorites, public.job_alerts, public.notification_preferences, public.notifications from anon, authenticated;
grant select, insert, delete on public.job_favorites, public.job_alerts to authenticated;
grant select, insert, update on public.notification_preferences to authenticated;
grant select, update (read_at) on public.notifications to authenticated;

create or replace function public.notify_new_message() returns trigger
language plpgsql security definer set search_path = '' as $$
declare v_recipient uuid;
begin
 select case when c.participant_a = new.sender_id then c.participant_b else c.participant_a end
 into v_recipient from public.conversations c where c.id = new.conversation_id;
 if v_recipient is not null and coalesce((select p.messages_enabled from public.notification_preferences p where p.user_id = v_recipient), true) then
  insert into public.notifications(recipient_id, kind, title, body, reference_id)
  values (v_recipient, 'message', 'Nouveau message', 'Vous avez reçu un nouveau message.', new.id)
  on conflict do nothing;
 end if;
 return new;
end; $$;
create trigger notify_message_insert after insert on public.messages
for each row execute function public.notify_new_message();

create or replace function public.notify_published_job() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if new.status = 'published' and (tg_op = 'INSERT' or old.status <> 'published') then
  insert into public.notifications(recipient_id, kind, title, body, reference_id)
  select distinct a.user_id, 'job', 'Une offre peut vous intéresser', new.title || ' · ' || new.city, new.id
  from public.job_alerts a
  left join public.notification_preferences p on p.user_id = a.user_id
  where a.user_id <> new.author_id and coalesce(p.jobs_enabled, true)
    and position(lower(btrim(a.keyword)) in lower(new.title || ' ' || new.description)) > 0
    and (a.city = '' or lower(btrim(a.city)) = lower(btrim(new.city)))
  on conflict do nothing;
 end if;
 return new;
end; $$;
create trigger notify_job_insert after insert on public.jobs
for each row execute function public.notify_published_job();
create trigger notify_job_publication after update of status on public.jobs
for each row execute function public.notify_published_job();
revoke all on function public.notify_new_message(), public.notify_published_job() from public, anon, authenticated;
