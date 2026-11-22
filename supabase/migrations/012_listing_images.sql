-- KUTANA-only image storage. Nothing from another Yaro project is reused.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('kutana-listing-images','kutana-listing-images',true,5242880,array['image/jpeg'])
on conflict (id) do nothing;

create table if not exists public.listing_images (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  storage_path text not null unique,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists listing_images_listing_idx on public.listing_images(listing_id,sort_order);
alter table public.listing_images enable row level security;
create policy "listing image public or owner read" on public.listing_images
  for select using (
    exists (select 1 from public.listings l where l.id = listing_id and
            (l.status = 'published' or l.seller_id = (select auth.uid())))
  );
revoke all on public.listing_images from public, anon, authenticated;
grant select on public.listing_images to anon, authenticated;
grant all on public.listing_images to service_role;

create policy "kutana owner uploads draft images" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'kutana-listing-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and exists (
      select 1 from public.listings l
      where l.id::text = (storage.foldername(name))[2]
        and l.seller_id = (select auth.uid()) and l.status = 'draft'
    )
  );

create or replace function public.attach_listing_image(p_listing uuid, p_path text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_id uuid; v_count int;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  perform 1 from public.listings where id = p_listing and seller_id = v_user and status = 'draft' for update;
  if not found then raise exception 'Draft unavailable' using errcode='42501'; end if;
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

-- Users must upload a real image before publishing a marketplace listing.
create or replace function public.publish_listing(p_listing uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_item public.listings%rowtype;
begin
  if v_user is null or not exists (
    select 1 from auth.users where id = v_user and email_confirmed_at is not null
  ) then raise exception 'Verified account required' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('kutana-listing'), pg_catalog.hashtext(v_user::text));
  select * into v_item from public.listings where id = p_listing and seller_id = v_user for update;
  if not found then raise exception 'Listing not found' using errcode='42501'; end if;
  if v_item.status <> 'draft' then raise exception 'Only drafts may be published' using errcode='22023'; end if;
  if not exists(select 1 from public.listing_images where listing_id = p_listing) then
    raise exception 'At least one photo is required' using errcode='22023';
  end if;
  if (select count(*) from public.listings
      where seller_id = v_user and published_at > pg_catalog.now() - interval '24 hours') >= 10 then
    raise exception 'Daily listing publication limit reached' using errcode='22023';
  end if;
  update public.listings set status = 'published', published_at = pg_catalog.now() where id = p_listing;
  return p_listing;
end; $$;
revoke all on function public.publish_listing(uuid) from public, anon, authenticated;
grant execute on function public.publish_listing(uuid) to authenticated;
