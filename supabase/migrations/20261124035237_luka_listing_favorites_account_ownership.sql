CREATE TABLE public.luka_listing_favorites (
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 listing_id uuid NOT NULL REFERENCES public.listings(id) ON DELETE CASCADE,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id, listing_id)
);
ALTER TABLE public.luka_listing_favorites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.luka_listing_favorites FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, DELETE ON public.luka_listing_favorites TO authenticated;
GRANT ALL ON public.luka_listing_favorites TO service_role;
CREATE POLICY "own listing favorites select" ON public.luka_listing_favorites FOR SELECT TO authenticated
 USING (user_id = (SELECT auth.uid()));
CREATE POLICY "own listing favorites insert" ON public.luka_listing_favorites FOR INSERT TO authenticated
 WITH CHECK (user_id = (SELECT auth.uid()) AND EXISTS (
   SELECT 1 FROM public.listings l WHERE l.id = listing_id
     AND l.status IN ('published', 'sold') AND (l.expires_at IS NULL OR l.expires_at > now())
 ));
CREATE POLICY "own listing favorites delete" ON public.luka_listing_favorites FOR DELETE TO authenticated
 USING (user_id = (SELECT auth.uid()));
