-- KUTANA project only. Harden default Supabase grants, which may include TRUNCATE/DELETE.
-- RLS does not protect TRUNCATE. Revoke broad privileges before allowing controlled operations.
revoke all privileges on table
  public.profiles, public.jobs, public.applications, public.listings,
  public.conversations, public.messages, public.application_events
  from public, anon, authenticated;

-- Server-side integrations use service_role; this role must NEVER be embedded in the app.
grant all privileges on table
  public.profiles, public.jobs, public.applications, public.listings,
  public.conversations, public.messages, public.application_events
  to service_role;

-- Guests only see the RLS-filtered published catalog.
grant select on public.jobs, public.listings to anon;

-- Profiles: each user may view and edit only their own row (enforced by RLS).
grant select, insert, update on public.profiles to authenticated;

-- Jobs and listings: direct client writes disabled; drafts via validated RPC only.
grant select on public.jobs, public.listings to authenticated;

-- Applications: own submission via insert policy or the apply_to_job RPC.
-- Status transitions are server-side only.
grant select, insert on public.applications to authenticated;

-- Conversations are started via a validated server RPC; messages may be sent by participants.
grant select on public.conversations to authenticated;
grant select, insert on public.messages to authenticated;

-- Recruitment audit is append-only from server functions.
grant select on public.application_events to authenticated;

-- Explicitly deny accidental future default grants on new KUTANA tables.
alter default privileges for role postgres in schema public
  revoke all privileges on tables from anon, authenticated;
