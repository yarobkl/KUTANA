-- RPC for authenticated candidates. KUTANA-only, after 004.
-- Server checks published status, candidate identity, and self-application prevention.
create or replace function public.apply_to_job(p_job uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_candidate uuid := auth.uid(); v_author uuid; v_status public.job_status; v_id uuid;
begin
    if v_candidate is null then
        raise exception 'Not authenticated' using errcode='42501';
    end if;
    select author_id, status into v_author, v_status from public.jobs where id = p_job;
    if not found or v_status <> 'published' then
        raise exception 'Offer unavailable' using errcode='22023';
    end if;
    if v_author = v_candidate then
        raise exception 'Cannot apply to your own offer' using errcode='42501';
    end if;
    insert into public.applications(job_id,candidate_id,status)
        values (p_job,v_candidate,'submitted')
        on conflict (job_id,candidate_id) do nothing returning id into v_id;
    if v_id is null then
        select id into v_id from public.applications
        where job_id = p_job and candidate_id = v_candidate;
    end if;
    return v_id;
end;
$$;
revoke all on function public.apply_to_job(uuid) from public, anon;
grant execute on function public.apply_to_job(uuid) to authenticated;
