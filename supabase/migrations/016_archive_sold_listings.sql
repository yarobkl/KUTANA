-- A sold listing can also be hidden later while its history stays in the owner's archive.
create or replace function public.change_listing_status(p_listing uuid, p_status public.listing_status)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := auth.uid(); v_current public.listing_status;
begin
  if v_user is null then raise exception 'Not authenticated' using errcode='42501'; end if;
  select status into v_current from public.listings
    where id = p_listing and seller_id = v_user for update;
  if not found then raise exception 'Listing unavailable' using errcode='42501'; end if;
  if (v_current = 'published' and p_status in ('archived','sold'))
     or (v_current = 'sold' and p_status = 'archived') then
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
