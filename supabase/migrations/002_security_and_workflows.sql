-- Apply after 001_initial.sql to a dedicated KUTANA project.
-- No client may mutate recruitment outcomes directly.
-- Make account visibility private by default (001 was too permissive).
drop policy if exists "profile public read" on public.profiles;
create policy "profile own read" on public.profiles for select to authenticated using (id = (select auth.uid()));

-- Restrict all role privileges as defense in depth alongside RLS.
revoke all on public.profiles, public.jobs, public.applications, public.listings,
 public.conversations, public.messages from anon;
grant select on public.jobs, public.listings to anon;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.jobs, public.listings to authenticated;
grant select, insert on public.applications to authenticated;
grant select on public.conversations to authenticated;
grant select, insert on public.messages to authenticated;

-- Protect conversation messages from spam and self-messaging; only server-created conversations.
create index if not exists applications_candidate_created_idx on public.applications(candidate_id,created_at desc);
create index if not exists applications_job_idx on public.applications(job_id);
create index if not exists conversations_a_idx on public.conversations(participant_a);
create index if not exists conversations_b_idx on public.conversations(participant_b);
create index if not exists listings_seller_idx on public.listings(seller_id);

-- Append-only status history for audit and user notifications.
create table if not exists public.application_events (
 id uuid primary key default gen_random_uuid(),
 application_id uuid not null references public.applications(id) on delete cascade,
 actor_id uuid not null references public.profiles(id),
 previous_status public.application_status,
 next_status public.application_status not null,
 created_at timestamptz not null default now()
);
alter table public.application_events enable row level security;
create policy "candidate or recruiter can view status history" on public.application_events
 for select to authenticated using (exists (
  select 1 from public.applications a join public.jobs j on j.id = a.job_id
  where a.id = application_id and (a.candidate_id = (select auth.uid()) or j.author_id = (select auth.uid()))
 ));
grant select on public.application_events to authenticated;

-- Security definer RPC with fixed search_path; recruiter must own the associated job.
create or replace function public.change_application_status(p_application uuid, p_next public.application_status)
returns void language plpgsql security definer set search_path = '' as $$
declare v_app public.applications%rowtype;
begin
 select a.* into v_app from public.applications a join public.jobs j on j.id = a.job_id
 where a.id = p_application and j.author_id = auth.uid() for update of a;
 if not found then raise exception 'Not authorized' using errcode='42501'; end if;
 if p_next = 'submitted' then raise exception 'Invalid status transition'; end if;
 if v_app.status in ('rejected','hired') then raise exception 'Final status cannot be changed'; end if;
 if v_app.status = p_next then return; end if;
 update public.applications set status = p_next where id = p_application;
 insert into public.application_events(application_id,actor_id,previous_status,next_status)
 values (p_application,auth.uid(),v_app.status,p_next);
end; $$;
revoke all on function public.change_application_status(uuid,public.application_status) from public;
grant execute on function public.change_application_status(uuid,public.application_status) to authenticated;

-- Conversation creation only after candidate has applied for a job belonging to the recruiter.
create or replace function public.start_application_conversation(p_application uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_candidate uuid; v_recruiter uuid; v_existing uuid;
begin
 select a.candidate_id,j.author_id into v_candidate,v_recruiter
 from public.applications a join public.jobs j on j.id=a.job_id where a.id=p_application;
 if v_candidate is null or auth.uid() not in (v_candidate,v_recruiter) then
  raise exception 'Not authorized' using errcode='42501';
 end if;
 select id into v_existing from public.conversations
 where (participant_a=v_candidate and participant_b=v_recruiter)
 or (participant_a=v_recruiter and participant_b=v_candidate) limit 1;
 if v_existing is not null then return v_existing; end if;
 insert into public.conversations(participant_a,participant_b)
 values (v_candidate,v_recruiter) returning id into v_existing;
 return v_existing;
end; $$;
revoke all on function public.start_application_conversation(uuid) from public;
grant execute on function public.start_application_conversation(uuid) to authenticated;
-- NOTE: add a canonical participant pair unique index and retry on unique_violation before production.
