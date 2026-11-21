-- KUTANA dedicated Supabase project ONLY. Apply after 001-003.
-- New signups previously had no matching public.profiles row, blocking jobs/listings.
-- auth.users metadata is untrusted presentation content, never a privilege.
create or replace function public.kutana_create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name)
  values (new.id, left(coalesce(new.raw_user_meta_data ->> 'display_name', ''), 120))
  on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function public.kutana_create_profile() from public, anon, authenticated;

drop trigger if exists kutana_new_user_profile on auth.users;
create trigger kutana_new_user_profile
  after insert on auth.users
  for each row execute function public.kutana_create_profile();

-- Close account-enumeration channels: only own private profile is readable.
-- Preserve existing private RLS policies from migration 002.
-- Explicitly revoke EXECUTE on security-definer helpers that aren't public RPCs.
revoke all on function public.guard_owner_fields() from public, anon, authenticated;

-- Function calls should always require an authenticated identity.
create or replace function public.start_application_conversation(p_application uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_candidate uuid; v_recruiter uuid; v_existing uuid;
begin
  if auth.uid() is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  select a.candidate_id, j.author_id into v_candidate, v_recruiter
  from public.applications a join public.jobs j on j.id=a.job_id where a.id=p_application;
  if v_candidate is null or auth.uid() not in (v_candidate,v_recruiter) then
    raise exception 'Not authorized' using errcode='42501';
  end if;
  -- Atomic canonical pair uniqueness added in migration 003.
  insert into public.conversations(participant_a,participant_b)
    values (least(v_candidate,v_recruiter),greatest(v_candidate,v_recruiter))
    on conflict do nothing returning id into v_existing;
  if v_existing is null then
    select id into v_existing from public.conversations
    where least(participant_a,participant_b)=least(v_candidate,v_recruiter)
      and greatest(participant_a,participant_b)=greatest(v_candidate,v_recruiter);
  end if;
  return v_existing;
end;
$$;
revoke all on function public.start_application_conversation(uuid) from public, anon;
grant execute on function public.start_application_conversation(uuid) to authenticated;
