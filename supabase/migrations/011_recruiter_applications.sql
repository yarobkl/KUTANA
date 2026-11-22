-- KUTANA-only recruiter inbox. Exposes applicant name only to the job owner.
-- SECURITY DEFINER is intentional: profile names are private under the normal RLS policy.
create or replace function public.received_applications()
returns table (
  id uuid, job_id uuid, candidate_id uuid, status public.application_status,
  created_at timestamptz, job_title text, company text, candidate_name text
)
language sql stable security definer set search_path = '' as $$
  select a.id, a.job_id, a.candidate_id, a.status, a.created_at,
         j.title as job_title, j.company,
         coalesce(nullif(pg_catalog.btrim(p.display_name),''),'Candidat') as candidate_name
  from public.applications a
  join public.jobs j on j.id = a.job_id
  join public.profiles p on p.id = a.candidate_id
  where j.author_id = auth.uid()
  order by a.created_at desc limit 100;
$$;
revoke all on function public.received_applications() from public, anon, authenticated;
grant execute on function public.received_applications() to authenticated;
