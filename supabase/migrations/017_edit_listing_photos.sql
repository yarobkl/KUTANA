-- Owners can add or replace images while a listing is draft, live or archived.
drop policy if exists "kutana owner uploads draft images" on storage.objects;
create policy "kutana owner adds listing images" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'kutana-listing-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (select 1 from public.listings l
      where l.id::text = (storage.foldername(name))[2]
        and l.seller_id = (select auth.uid())
        and l.status in ('draft','published','archived'))
  );
create policy "kutana owner reads listing image objects" on storage.objects
  for select to authenticated using (
    bucket_id = 'kutana-listing-images'
    and exists (select 1 from public.listing_images i
      join public.listings l on l.id = i.listing_id
      where i.storage_path = name and l.seller_id = (select auth.uid()))
  );
create policy "kutana owner replaces listing image objects" on storage.objects
  for update to authenticated using (
    bucket_id = 'kutana-listing-images'
    and exists (select 1 from public.listing_images i
      join public.listings l on l.id = i.listing_id
      where i.storage_path = name and l.seller_id = (select auth.uid())
        and l.status in ('draft','published','archived'))
  ) with check (
    bucket_id = 'kutana-listing-images'
    and exists (select 1 from public.listing_images i
      join public.listings l on l.id = i.listing_id
      where i.storage_path = name and l.seller_id = (select auth.uid())
        and l.status in ('draft','published','archived'))
  );

create or replace function public.attach_listing_image(p_listing uuid, p_path text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_id uuid; v_count int;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  perform 1 from public.listings where id = p_listing and seller_id = v_user
    and status in ('draft','published','archived') for update;
  if not found then raise exception 'Listing unavailable' using errcode='42501'; end if;
  if p_path is null or pg_catalog.split_part(p_path,'/',1) <> v_user::text
     or pg_catalog.split_part(p_path,'/',2) <> p_listing::text
     or pg_catalog.split_part(p_path,'/',4) <> ''
     or pg_catalog.right(p_path,4) <> '.jpg'
     or not exists(select 1 from storage.objects where bucket_id='kutana-listing-images' and name=p_path) then
    raise exception 'Invalid image' using errcode='22023';
  end if;
  select count(*) into v_count from public.listing_images where listing_id = p_listing;
  if v_count >= 5 then raise exception 'Maximum five images' using errcode='22023'; end if;
  insert into public.listing_images(listing_id,storage_path,sort_order)
    values(p_listing,p_path,v_count) returning id into v_id;
  return v_id;
end; $$;
revoke all on function public.attach_listing_image(uuid,text) from public, anon, authenticated;
grant execute on function public.attach_listing_image(uuid,text) to authenticated;
