-- Signed-in users can submit a product issue. Contact details are never client-controlled.
create table public.problem_reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references auth.users(id) on delete cascade,
 details text not null check (char_length(btrim(details)) between 10 and 4000),
 app_version text not null default '' check (char_length(app_version) <= 40),
 created_at timestamptz not null default now(),
 email_delivered_at timestamptz
);
create index problem_reports_reporter_created_idx on public.problem_reports(reporter_id, created_at desc);
alter table public.problem_reports enable row level security;
create policy "reporter reads own issues" on public.problem_reports
 for select to authenticated using (reporter_id = (select auth.uid()));
revoke all on public.problem_reports from anon, authenticated;
grant select on public.problem_reports to authenticated;
grant all on public.problem_reports to service_role;

create or replace function public.submit_problem_report(p_details text, p_app_version text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_id uuid; v_details text := btrim(p_details);
begin
 if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
 if v_details is null or char_length(v_details) not between 10 and 4000 or char_length(coalesce(p_app_version,'')) > 40 then
  raise exception 'Invalid report' using errcode='22023';
 end if;
 if (select count(*) from public.problem_reports
     where reporter_id=v_user and created_at > pg_catalog.now() - interval '1 hour') >= 5 then
  raise exception 'Too many reports' using errcode='22023';
 end if;
 insert into public.problem_reports(reporter_id, details, app_version)
 values (v_user, v_details, coalesce(p_app_version,'')) returning id into v_id;
 return v_id;
end; $$;
revoke all on function public.submit_problem_report(text,text) from public, anon;
grant execute on function public.submit_problem_report(text,text) to authenticated;
