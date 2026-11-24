CREATE TABLE public.luka_listing_relist_events (
 id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 listing_id uuid NOT NULL REFERENCES public.listings(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX luka_listing_relist_events_user_time ON public.luka_listing_relist_events(user_id, created_at DESC);
ALTER TABLE public.luka_listing_relist_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.luka_listing_relist_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.luka_listing_relist_events TO service_role;
CREATE OR REPLACE FUNCTION public.change_listing_status(p_listing uuid, p_status public.listing_status)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE v_user uuid := auth.uid(); v_current public.listing_status;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('luka-relist'),pg_catalog.hashtext(v_user::text));
 SELECT status INTO v_current FROM public.listings WHERE id=p_listing AND seller_id=v_user FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Listing unavailable' USING ERRCODE='42501'; END IF;
 IF (v_current='published' AND p_status IN ('archived','sold')) OR (v_current='sold' AND p_status='archived') THEN
   UPDATE public.listings SET status=p_status WHERE id=p_listing;
 ELSIF v_current='archived' AND p_status='published' THEN
   IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id=v_user AND email_confirmed_at IS NOT NULL)
      OR NOT EXISTS (SELECT 1 FROM public.listing_images WHERE listing_id=p_listing) THEN
     RAISE EXCEPTION 'Verified account and photo required' USING ERRCODE='42501';
   END IF;
   IF (SELECT count(*) FROM public.luka_listing_relist_events WHERE user_id=v_user AND created_at>pg_catalog.now()-interval '24 hours') >= 3 THEN
     RAISE EXCEPTION 'Relisting limit reached; try again later' USING ERRCODE='22023';
   END IF;
   UPDATE public.listings SET status='published', published_at=pg_catalog.now() WHERE id=p_listing;
   INSERT INTO public.luka_listing_relist_events(user_id,listing_id) VALUES(v_user,p_listing);
 ELSE
   RAISE EXCEPTION 'Invalid listing transition' USING ERRCODE='22023';
 END IF;
 RETURN p_listing;
END;
$function$;
REVOKE ALL ON FUNCTION public.change_listing_status(uuid,public.listing_status) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_listing_status(uuid,public.listing_status) TO authenticated;
