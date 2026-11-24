CREATE OR REPLACE FUNCTION public.start_listing_conversation(p_listing uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $body$
DECLARE v_user uuid := auth.uid(); v_seller uuid; v_id uuid;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501'; END IF;
  SELECT seller_id INTO v_seller FROM public.listings
   WHERE id = p_listing AND status = 'published'
     AND (expires_at IS NULL OR expires_at > pg_catalog.now());
  IF v_seller IS NULL OR v_seller = v_user THEN
    RAISE EXCEPTION 'Listing unavailable' USING ERRCODE='42501';
  END IF;
  INSERT INTO public.conversations(participant_a,participant_b)
    VALUES (v_user,v_seller) ON CONFLICT DO NOTHING RETURNING id INTO v_id;
  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM public.conversations
    WHERE (participant_a = v_user AND participant_b = v_seller)
       OR (participant_b = v_user AND participant_a = v_seller) LIMIT 1;
  END IF;
  IF v_id IS NULL THEN RAISE EXCEPTION 'Could not start conversation'; END IF;
  RETURN v_id;
END; $body$;

