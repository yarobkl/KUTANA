-- KUTANA-only. Run after 001-005 in the NEW dedicated project.
-- Authenticated users may create drafts, but cannot publicly publish or alter
-- listing ownership/status via direct PostgREST writes. Future moderation
-- / publishing flows must be added as separate validated server-side RPCs.

revoke insert, update on public.jobs, public.listings from authenticated;

create or replace function public.create_job_draft(
  p_title text, p_company text, p_city text, p_contract_type text, p_description text
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  p_title := btrim(p_title);
  p_company := btrim(p_company);
  p_city := btrim(p_city);
  p_description := btrim(p_description);
  if char_length(p_title) not between 5 and 160 or char_length(p_company) not between 2 and 160
    or char_length(p_city) not between 2 and 120 or char_length(p_description) not between 30 and 12000
    or p_contract_type is null or p_contract_type not in ('CDI','CDD','Stage','Alternance','Intérim','Freelance','Autre') then
      raise exception 'Invalid job draft' using errcode='22023';
  end if;
  insert into public.jobs(author_id,title,company,city,contract_type,description,status)
    values(v_user,p_title,p_company,p_city,p_contract_type,p_description,'draft')
    returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.create_job_draft(text,text,text,text,text) from public, anon;
grant execute on function public.create_job_draft(text,text,text,text,text) to authenticated;

create or replace function public.create_listing_draft(
  p_category text, p_title text, p_description text, p_city text, p_price_xaf bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid; v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  p_title := btrim(p_title);
  p_description := btrim(p_description);
  p_city := btrim(p_city);
  if p_category is null or p_category not in ('Téléphones','Informatique','Électroménager','Meubles','Véhicules','Mode','Maison','Matériel professionnel','Autres')
    or char_length(p_title) not between 3 and 160 or char_length(p_city) not between 2 and 120
    or char_length(p_description) not between 10 and 12000
    or p_price_xaf is null or p_price_xaf < 0 or p_price_xaf > 100000000000 then
      raise exception 'Invalid listing draft' using errcode='22023';
  end if;
  insert into public.listings(seller_id,category,title,description,city,price_xaf,status)
    values(v_user,p_category,p_title,p_description,p_city,p_price_xaf,'draft')
    returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.create_listing_draft(text,text,text,text,bigint) from public, anon;
grant execute on function public.create_listing_draft(text,text,text,text,bigint) to authenticated;
