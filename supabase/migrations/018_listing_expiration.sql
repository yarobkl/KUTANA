-- A listing is visible for 30 days per publication. Expiry archives it without deleting photos or history.
alter table public.listings add column if not exists expires_at timestamptz;
update public.listings set expires_at = published_at + interval '30 days'
where published_at is not null and expires_at is null;

create or replace function public.set_listing_expiration()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'published' and old.status is distinct from 'published' then
    new.expires_at := coalesce(new.published_at, pg_catalog.now()) + interval '30 days';
  end if;
  return new;
end; $$;
create trigger listing_publication_expires before update of status on public.listings
for each row execute function public.set_listing_expiration();

create or replace function public.archive_expired_listings()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  update public.listings set status = 'archived'
    where status in ('published','sold') and expires_at <= pg_catalog.now();
  get diagnostics v_count = row_count;
  return v_count;
end; $$;
revoke all on function public.archive_expired_listings() from public, anon, authenticated;
grant execute on function public.archive_expired_listings() to postgres;

-- Access stops at the deadline even before the next scheduled archive run.
drop policy if exists "visible listings or own" on public.listings;
create policy "visible listings or own" on public.listings for select using (
  (status in ('published','sold') and (expires_at is null or expires_at > pg_catalog.now()))
  or seller_id = (select auth.uid())
);
drop policy if exists "listing image public or owner read" on public.listing_images;
create policy "listing image public or owner read" on public.listing_images for select using (
  exists (select 1 from public.listings l where l.id = listing_id and
    ((l.status in ('published','sold') and (l.expires_at is null or l.expires_at > pg_catalog.now()))
      or l.seller_id = (select auth.uid())))
);

create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('kutana-archive-expired-listings', '5 * * * *',
  'select public.archive_expired_listings()');
