-- KUTANA-only private CV storage and scoped recruiter/candidate retrieval.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('kutana-cvs','kutana-cvs',false,5242880,array['application/pdf'])
on conflict (id) do nothing;

create table if not exists public.application_cvs (
  application_id uuid primary key references public.applications(id) on delete cascade,
  storage_path text not null unique,
  file_name text not null check (char_length(file_name) between 1 and 160),
  created_at timestamptz not null default now()
);
alter table public.application_cvs enable row level security;
create policy "CV candidate and recruiter read" on public.application_cvs
  for select to authenticated using (
    exists(
      select 1 from public.applications a
      join public.jobs j on j.id = a.job_id
      where a.id = application_id and
            (a.candidate_id = (select auth.uid()) or j.author_id = (select auth.uid()))
    )
  );
revoke all on public.application_cvs from public, anon, authenticated;
grant select on public.application_cvs to authenticated;
grant all on public.application_cvs to service_role;

create policy "kutana CV candidate uploads" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'kutana-cvs' and (storage.foldername(name))[1] = (select auth.uid())::text
  );
create policy "kutana CV participant downloads" on storage.objects
  for select to authenticated using (
    bucket_id = 'kutana-cvs' and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (
        select 1 from public.application_cvs c
        join public.applications a on a.id = c.application_id
        join public.jobs j on j.id = a.job_id
        where c.storage_path = name and j.author_id = (select auth.uid())
      )
    )
  );

create or replace function public.attach_application_cv(
  p_application uuid, p_path text, p_file_name text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_clean text := pg_catalog.btrim(p_file_name);
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  perform 1 from public.applications a
    where a.id = p_application and a.candidate_id = v_user for update;
  if not found then raise exception 'Application unavailable' using errcode='42501'; end if;
  if v_clean is null or char_length(v_clean) not between 1 and 160
     or p_path is null or pg_catalog.split_part(p_path,'/',1) <> v_user::text
     or pg_catalog.split_part(p_path,'/',3) <> ''
     or pg_catalog.right(p_path,4) <> '.pdf'
     or not exists (
       select 1 from storage.objects
        where bucket_id = 'kutana-cvs' and name = p_path
     ) then
    raise exception 'Invalid CV file' using errcode='22023';
  end if;
  insert into public.application_cvs(application_id,storage_path,file_name)
    values(p_application,p_path,v_clean)
    on conflict(application_id) do update
      set storage_path = excluded.storage_path,
          file_name = excluded.file_name,
          created_at = pg_catalog.now();
  return p_application;
end; $$;
revoke all on function public.attach_application_cv(uuid,text,text) from public, anon, authenticated;
grant execute on function public.attach_application_cv(uuid,text,text) to authenticated;
