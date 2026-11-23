-- Owner-controlled marketplace lifecycle. Archived content remains private and recoverable.
create or replace function public.edit_listing(
  p_listing uuid, p_category text, p_title text, p_description text,
  p_city text, p_price_xaf bigint
) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_status public.listing_status;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  select status into v_status from public.listings
    where id = p_listing and seller_id = v_user for update;
  if not found or v_status = 'sold' then
    raise exception 'Listing cannot be edited' using errcode='42501';
  end if;
  if p_category not in ('Téléphones','Informatique','Électroménager','Meubles','Véhicules','Mode','Maison','Matériel professionnel','Autres')
     or char_length(pg_catalog.btrim(p_title)) not between 3 and 160
     or char_length(pg_catalog.btrim(p_description)) not between 10 and 12000
     or char_length(pg_catalog.btrim(p_city)) not between 2 and 120
     or p_price_xaf is null or p_price_xaf not between 0 and 100000000000 then
    raise exception 'Invalid listing details' using errcode='22023';
  end if;
  update public.listings set category = p_category, title = pg_catalog.btrim(p_title),
    description = pg_catalog.btrim(p_description), city = pg_catalog.btrim(p_city),
    price_xaf = p_price_xaf where id = p_listing;
  return p_listing;
end; $$;
revoke all on function public.edit_listing(uuid,text,text,text,text,bigint) from public, anon, authenticated;
grant execute on function public.edit_listing(uuid,text,text,text,text,bigint) to authenticated;

create or replace function public.change_listing_status(p_listing uuid, p_status public.listing_status)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_current public.listing_status;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  select status into v_current from public.listings
    where id = p_listing and seller_id = v_user for update;
  if not found then raise exception 'Listing unavailable' using errcode='42501'; end if;
  if (v_current = 'published' and p_status in ('archived','sold')) then
    update public.listings set status = p_status where id = p_listing;
  elsif (v_current = 'archived' and p_status = 'published') then
    if not exists (select 1 from auth.users where id = v_user and email_confirmed_at is not null)
       or not exists (select 1 from public.listing_images where listing_id = p_listing) then
      raise exception 'Verified account and photo required' using errcode='42501';
    end if;
    update public.listings set status = 'published', published_at = pg_catalog.now() where id = p_listing;
  else
    raise exception 'Invalid listing transition' using errcode='22023';
  end if;
  return p_listing;
end; $$;
revoke all on function public.change_listing_status(uuid,public.listing_status) from public, anon, authenticated;
grant execute on function public.change_listing_status(uuid,public.listing_status) to authenticated;

-- Buyers may continue to see the sold badge, including images, but cannot open new conversations.
drop policy if exists "published listings or own" on public.listings;
create policy "visible listings or own" on public.listings for select
  using (status in ('published','sold') or seller_id = (select auth.uid()));
drop policy if exists "listing image public or owner read" on public.listing_images;
create policy "listing image public or owner read" on public.listing_images for select using (
  exists (select 1 from public.listings l where l.id = listing_id and
    (l.status in ('published','sold') or l.seller_id = (select auth.uid())))
);
