-- KUTANA-only migration; run only on a newly provisioned KUTANA Supabase project.
-- Protect listing and job ownership/status fields against unauthorized edits.
create or replace function public.guard_owner_fields() returns trigger
language plpgsql set search_path = '' as $$
begin
 if tg_table_name = 'jobs' then
  if new.author_id is distinct from old.author_id then raise exception 'Owner cannot change'; end if;
 elsif tg_table_name = 'listings' then
  if new.seller_id is distinct from old.seller_id then raise exception 'Owner cannot change'; end if;
 end if;
 return new;
end $$;
create trigger jobs_owner_immutable before update on public.jobs
 for each row execute function public.guard_owner_fields();
create trigger listings_owner_immutable before update on public.listings
 for each row execute function public.guard_owner_fields();

-- Canonical conversation pairs; prevents duplicate threads regardless of participant order.
create unique index conversations_pair_unique on public.conversations
 (least(participant_a, participant_b), greatest(participant_a, participant_b));

-- Tighten free-form fields and avoid unusable content.
alter table public.jobs add constraint jobs_description_length check (char_length(description) between 30 and 12000);
alter table public.listings add constraint listings_description_length check (char_length(description) between 10 and 12000);
alter table public.listings add constraint listings_price_reasonable check (price_xaf <= 100000000000);

-- Do not expose email addresses or private identity fields in public listing/job DTOs.
-- Status-change RPC already checks recruiter ownership; notifications must be sent server-side.
