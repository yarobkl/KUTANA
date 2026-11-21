-- KUTANA initial schema. Run on a NEW Supabase project after review.
create extension if not exists pgcrypto;
create type public.job_status as enum ('draft','published','closed');
create type public.application_status as enum ('submitted','viewed','shortlisted','interview','rejected','hired');
create type public.listing_status as enum ('draft','published','reserved','sold','archived');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '',
 city text,
 bio text,
 created_at timestamptz not null default now()
);
create table public.jobs (
 id uuid primary key default gen_random_uuid(),
 author_id uuid not null references public.profiles(id),
 title text not null check (char_length(title) between 5 and 160),
 company text not null,
 city text not null,
 contract_type text not null,
 description text not null,
 status public.job_status not null default 'draft',
 created_at timestamptz not null default now()
);
create table public.applications (
 id uuid primary key default gen_random_uuid(),
 job_id uuid not null references public.jobs(id) on delete cascade,
 candidate_id uuid not null references public.profiles(id),
 status public.application_status not null default 'submitted',
 created_at timestamptz not null default now(),
 unique(job_id,candidate_id)
);
create table public.listings (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.profiles(id),
 category text not null,
 title text not null check (char_length(title) between 3 and 160),
 description text not null,
 city text not null,
 price_xaf bigint not null check (price_xaf >= 0),
 status public.listing_status not null default 'draft',
 created_at timestamptz not null default now()
);
create table public.conversations (
 id uuid primary key default gen_random_uuid(),
 participant_a uuid not null references public.profiles(id),
 participant_b uuid not null references public.profiles(id),
 created_at timestamptz not null default now(),
 check (participant_a <> participant_b)
);
create table public.messages (
 id uuid primary key default gen_random_uuid(),
 conversation_id uuid not null references public.conversations(id) on delete cascade,
 sender_id uuid not null references public.profiles(id),
 body text not null check (char_length(body) between 1 and 4000),
 created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.jobs enable row level security;
alter table public.applications enable row level security;
alter table public.listings enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

create policy "profile public read" on public.profiles for select using (true);
create policy "profile own insert" on public.profiles for insert to authenticated with check (id = auth.uid());
create policy "profile own update" on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy "published jobs or own" on public.jobs for select using (status = 'published' or author_id = auth.uid());
create policy "jobs own insert" on public.jobs for insert to authenticated with check (author_id = auth.uid());
create policy "jobs own update" on public.jobs for update to authenticated using (author_id = auth.uid()) with check (author_id = auth.uid());
create policy "applications participant read" on public.applications for select to authenticated using (
 candidate_id = auth.uid() or exists (select 1 from public.jobs j where j.id = job_id and j.author_id = auth.uid())
);
create policy "applications candidate insert" on public.applications for insert to authenticated with check (
 candidate_id = auth.uid() and status = 'submitted' and exists (select 1 from public.jobs j where j.id = job_id and j.status = 'published' and j.author_id <> auth.uid())
);
-- Status changes intentionally have no client UPDATE policy; use validated server functions.
create policy "published listings or own" on public.listings for select using (status = 'published' or seller_id = auth.uid());
create policy "listings own insert" on public.listings for insert to authenticated with check (seller_id = auth.uid());
create policy "listings own update" on public.listings for update to authenticated using (seller_id = auth.uid()) with check (seller_id = auth.uid());
create policy "conversation participants read" on public.conversations for select to authenticated using (auth.uid() in (participant_a,participant_b));
-- Conversation creation must be validated through server-side RPC to prevent unsolicited threads.
create policy "messages participants read" on public.messages for select to authenticated using (
 exists (select 1 from public.conversations c where c.id = conversation_id and auth.uid() in (c.participant_a,c.participant_b))
);
create policy "messages participant insert" on public.messages for insert to authenticated with check (
 sender_id = auth.uid() and exists (select 1 from public.conversations c where c.id = conversation_id and auth.uid() in (c.participant_a,c.participant_b))
);
create index jobs_published_city_idx on public.jobs(city,created_at desc) where status='published';
create index listings_published_city_idx on public.listings(city,created_at desc) where status='published';
create index messages_conversation_created_idx on public.messages(conversation_id,created_at desc);
