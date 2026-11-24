REVOKE ALL ON SEQUENCE public.luka_listing_relist_events_id_seq FROM PUBLIC, anon, authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.luka_listing_relist_events_id_seq TO service_role;
