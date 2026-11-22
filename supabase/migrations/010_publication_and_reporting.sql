-- KUTANA-only. Explicit author publication after email verification, plus abuse reports.
-- Existing drafts remain private; no previously saved content is published here.
alter table public.jobs add column if not exists published_at timestamptz;
alter table public.listings add column if not exists published_at timestamptz;

create index if not exists jobs_author_status_idx on public.jobs(author_id, status, created_at desc);
create index if not exists listings_seller_status_idx on public.listings(seller_id, status, created_at desc);

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  content_kind text not null check (content_kind in ('job', 'listing')),
  content_id uuid not null,
  reason text not null check (char_length(reason) between 10 and 2000),
  created_at timestamptz not null default now(),
  unique (reporter_id, content_kind, content_id)
);
alter table public.content_reports enable row level security;
revoke all privileges on table public.content_reports from public, anon, authenticated;
grant all privileges on table public.content_reports to service_role;

create or replace function public.publish_job(p_job uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_job public.jobs%rowtype;
begin
  if v_user is null or not exists (
    select 1 from auth.users where id = v_user and email_confirmed_at is not null
  ) then raise exception 'Verified account required' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('kutana-job'), pg_catalog.hashtext(v_user::text));
  select * into v_job from public.jobs where id = p_job and author_id = v_user for update;
  if not found then raise exception 'Job not found' using errcode='42501'; end if;
  if v_job.status <> 'draft' then raise exception 'Only drafts may be published' using errcode='22023'; end if;
  if (select count(*) from public.jobs
      where author_id = v_user and published_at > pg_catalog.now() - interval '24 hours') >= 5 then
    raise exception 'Daily job publication limit reached' using errcode='22023';
  end if;
  update public.jobs set status = 'published', published_at = pg_catalog.now() where id = p_job;
  return p_job;
end; $$;
revoke all on function public.publish_job(uuid) from public, anon, authenticated;
grant execute on function public.publish_job(uuid) to authenticated;

create or replace function public.publish_listing(p_listing uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_item public.listings%rowtype;
begin
  if v_user is null or not exists (
    select 1 from auth.users where id = v_user and email_confirmed_at is not null
  ) then raise exception 'Verified account required' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('kutana-listing'), pg_catalog.hashtext(v_user::text));
  select * into v_item from public.listings where id = p_listing and seller_id = v_user for update;
  if not found then raise exception 'Listing not found' using errcode='42501'; end if;
  if v_item.status <> 'draft' then raise exception 'Only drafts may be published' using errcode='22023'; end if;
  if (select count(*) from public.listings
      where seller_id = v_user and published_at > pg_catalog.now() - interval '24 hours') >= 10 then
    raise exception 'Daily listing publication limit reached' using errcode='22023';
  end if;
  update public.listings set status = 'published', published_at = pg_catalog.now() where id = p_listing;
  return p_listing;
end; $$;
revoke all on function public.publish_listing(uuid) from public, anon, authenticated;
grant execute on function public.publish_listing(uuid) to authenticated;

create or replace function public.withdraw_publication(p_kind text, p_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  if p_kind = 'job' then
    update public.jobs set status = 'closed' where id = p_id and author_id = v_user and status = 'published';
  elsif p_kind = 'listing' then
    update public.listings set status = 'archived' where id = p_id and seller_id = v_user and status = 'published';
  else raise exception 'Invalid content kind' using errcode='22023';
  end if;
  if not found then raise exception 'Publication unavailable' using errcode='42501'; end if;
  return p_id;
end; $$;
revoke all on function public.withdraw_publication(text,uuid) from public, anon, authenticated;
grant execute on function public.withdraw_publication(text,uuid) to authenticated;

create or replace function public.start_listing_conversation(p_listing uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_seller uuid; v_id uuid;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  select seller_id into v_seller from public.listings where id = p_listing and status = 'published';
  if v_seller is null or v_seller = v_user then
    raise exception 'Listing unavailable' using errcode='42501';
  end if;
  insert into public.conversations(participant_a,participant_b)
    values (v_user,v_seller) on conflict do nothing returning id into v_id;
  if v_id is null then
    select id into v_id from public.conversations
      where (participant_a = v_user and participant_b = v_seller)
         or (participant_b = v_user and participant_a = v_seller) limit 1;
  end if;
  if v_id is null then raise exception 'Could not start conversation'; end if;
  return v_id;
end; $$;
revoke all on function public.start_listing_conversation(uuid) from public, anon, authenticated;
grant execute on function public.start_listing_conversation(uuid) to authenticated;

create or replace function public.report_content(p_kind text, p_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_id uuid; v_reason text := btrim(p_reason);
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  if p_kind not in ('job','listing') or v_reason is null or char_length(v_reason) not between 10 and 2000 then
    raise exception 'Invalid report' using errcode='22023';
  end if;
  if p_kind = 'job' and not exists (select 1 from public.jobs where id = p_id and status = 'published' and author_id <> v_user) then
    raise exception 'Job unavailable' using errcode='42501';
  end if;
  if p_kind = 'listing' and not exists (select 1 from public.listings where id = p_id and status = 'published' and seller_id <> v_user) then
    raise exception 'Listing unavailable' using errcode='42501';
  end if;
  insert into public.content_reports(reporter_id, content_kind, content_id, reason)
    values(v_user,p_kind,p_id,v_reason)
    on conflict (reporter_id,content_kind,content_id) do update set reason = excluded.reason
    returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.report_content(text,uuid,text) from public, anon, authenticated;
grant execute on function public.report_content(text,uuid,text) to authenticated;
