# Commentaires publics LUKA

Migration Supabase appliquée : `20261123214504_luka_public_comments`.

Lecture publique limitée aux publications visibles, écriture et réponses par utilisateur authentifié, suppression réservée à l'auteur, fermeture par le propriétaire, signalements privés et limitation à cinq commentaires par minute. La modération peut masquer un commentaire via le rôle serveur ; une interface de modération dédiée reste à créer.

Les vérifications SQL ont été réalisées dans des transactions annulées : lecture anonyme, ajout, réponse, refus de suppression par un autre auteur, signalement, fermeture et refus de nouvelle publication. Les comptes et données de test n'ont pas été conservés. Les parcours iOS complets et tests entre comptes réels restent à vérifier.

Cette définition est également versionnée dans `supabase/migrations/20261123214504_luka_public_comments.sql`.

```sql
CREATE TABLE public.luka_comment_settings (
  kind text NOT NULL CHECK (kind IN ('job','listing')),
  content_id uuid NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  PRIMARY KEY(kind,content_id)
);
CREATE TABLE public.luka_comments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('job','listing')),
  content_id uuid NOT NULL,
  parent_id uuid REFERENCES public.luka_comments(id) ON DELETE SET NULL,
  author_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  author_name text NOT NULL CHECK (char_length(author_name) BETWEEN 1 AND 120),
  body text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  created_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  hidden boolean NOT NULL DEFAULT false
);
CREATE INDEX luka_comments_content_idx ON public.luka_comments(kind,content_id,created_at);
CREATE INDEX luka_comments_author_rate_idx ON public.luka_comments(author_id,created_at DESC);
CREATE TABLE public.luka_comment_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 comment_id uuid NOT NULL REFERENCES public.luka_comments(id) ON DELETE CASCADE,
 reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 reason text NOT NULL CHECK (char_length(reason) BETWEEN 10 AND 1000),
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(comment_id,reporter_id)
);
ALTER TABLE public.luka_comment_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.luka_comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.luka_comment_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.luka_comment_settings, public.luka_comments, public.luka_comment_reports FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.luka_comment_settings, public.luka_comments, public.luka_comment_reports TO service_role;
CREATE OR REPLACE FUNCTION public.luka_comment_content_public(p_kind text,p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $body$
 SELECT CASE p_kind
 WHEN 'job' THEN EXISTS (SELECT 1 FROM public.jobs j WHERE j.id=p_id AND j.status='published')
 WHEN 'listing' THEN EXISTS (SELECT 1 FROM public.listings l WHERE l.id=p_id AND l.status IN ('published','sold') AND (l.expires_at IS NULL OR l.expires_at>pg_catalog.now()))
 ELSE false END
$body$;
REVOKE ALL ON FUNCTION public.luka_comment_content_public(text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.luka_comment_content_public(text,uuid) TO anon, authenticated;
GRANT SELECT ON public.luka_comment_settings, public.luka_comments TO anon, authenticated;
CREATE POLICY "public reads visible comments" ON public.luka_comments FOR SELECT TO anon, authenticated
 USING (NOT hidden AND public.luka_comment_content_public(kind,content_id));
CREATE POLICY "public reads comment settings" ON public.luka_comment_settings FOR SELECT TO anon, authenticated
 USING (public.luka_comment_content_public(kind,content_id));
CREATE OR REPLACE FUNCTION public.luka_add_comment(p_kind text,p_content uuid,p_parent uuid,p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
DECLARE v_user uuid := auth.uid(); v_name text; v_result uuid; v_body text := pg_catalog.btrim(p_body);
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501'; END IF;
 IF NOT public.luka_comment_content_public(p_kind,p_content) THEN RAISE EXCEPTION 'Content unavailable' USING ERRCODE='42501'; END IF;
 IF NOT COALESCE((SELECT enabled FROM public.luka_comment_settings WHERE kind=p_kind AND content_id=p_content),true)
 THEN RAISE EXCEPTION 'Comments closed' USING ERRCODE='42501'; END IF;
 IF v_body IS NULL OR pg_catalog.char_length(v_body) NOT BETWEEN 1 AND 2000 THEN RAISE EXCEPTION 'Invalid comment' USING ERRCODE='22023'; END IF;
 IF p_parent IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.luka_comments c WHERE c.id=p_parent AND c.kind=p_kind AND c.content_id=p_content AND NOT c.hidden AND c.deleted_at IS NULL)
 THEN RAISE EXCEPTION 'Reply unavailable' USING ERRCODE='22023'; END IF;
 PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text,0));
 IF (SELECT count(*) FROM public.luka_comments c WHERE c.author_id=v_user AND c.created_at > pg_catalog.now()-interval '1 minute') >= 5
 THEN RAISE EXCEPTION 'Rate limit exceeded' USING ERRCODE='P0001'; END IF;
 SELECT COALESCE(NULLIF(pg_catalog.btrim(display_name),''),'Membre LUKA') INTO v_name FROM public.profiles WHERE id=v_user;
 v_name := pg_catalog.left(COALESCE(v_name,'Membre LUKA'),120);
 INSERT INTO public.luka_comments(kind,content_id,parent_id,author_id,author_name,body)
 VALUES(p_kind,p_content,p_parent,v_user,v_name,v_body) RETURNING id INTO v_result;
 RETURN v_result;
END $body$;
CREATE OR REPLACE FUNCTION public.luka_delete_own_comment(p_comment uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501'; END IF;
 UPDATE public.luka_comments SET body='Commentaire supprimé',author_name='Membre LUKA',deleted_at=pg_catalog.now()
 WHERE id=p_comment AND author_id=auth.uid() AND deleted_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Comment unavailable' USING ERRCODE='42501'; END IF;
END $body$;
CREATE OR REPLACE FUNCTION public.luka_report_comment(p_comment uuid,p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
DECLARE v_user uuid := auth.uid(); v_reason text := pg_catalog.btrim(p_reason);
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501'; END IF;
 IF v_reason IS NULL OR pg_catalog.char_length(v_reason) NOT BETWEEN 10 AND 1000 THEN RAISE EXCEPTION 'Invalid reason' USING ERRCODE='22023'; END IF;
 IF NOT EXISTS (SELECT 1 FROM public.luka_comments c WHERE c.id=p_comment AND NOT c.hidden AND c.deleted_at IS NULL AND c.author_id<>v_user AND public.luka_comment_content_public(c.kind,c.content_id))
 THEN RAISE EXCEPTION 'Comment unavailable' USING ERRCODE='42501'; END IF;
 INSERT INTO public.luka_comment_reports(comment_id,reporter_id,reason) VALUES(p_comment,v_user,v_reason)
 ON CONFLICT(comment_id,reporter_id) DO NOTHING;
END $body$;
CREATE OR REPLACE FUNCTION public.luka_set_comments_enabled(p_kind text,p_content uuid,p_enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $body$
DECLARE v_user uuid := auth.uid(); v_owner uuid;
BEGIN
 IF v_user IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='42501'; END IF;
 IF p_kind='job' THEN SELECT author_id INTO v_owner FROM public.jobs WHERE id=p_content;
 ELSIF p_kind='listing' THEN SELECT seller_id INTO v_owner FROM public.listings WHERE id=p_content;
 ELSE RAISE EXCEPTION 'Invalid kind' USING ERRCODE='22023'; END IF;
 IF v_owner IS NULL OR v_owner<>v_user THEN RAISE EXCEPTION 'Not authorized' USING ERRCODE='42501'; END IF;
 IF p_enabled IS NULL THEN RAISE EXCEPTION 'Invalid value' USING ERRCODE='22023'; END IF;
 INSERT INTO public.luka_comment_settings(kind,content_id,enabled) VALUES(p_kind,p_content,p_enabled)
 ON CONFLICT(kind,content_id) DO UPDATE SET enabled=EXCLUDED.enabled;
END $body$;
REVOKE ALL ON FUNCTION public.luka_add_comment(text,uuid,uuid,text), public.luka_delete_own_comment(uuid), public.luka_report_comment(uuid,text), public.luka_set_comments_enabled(text,uuid,boolean) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.luka_add_comment(text,uuid,uuid,text), public.luka_delete_own_comment(uuid), public.luka_report_comment(uuid,text), public.luka_set_comments_enabled(text,uuid,boolean) TO authenticated;
```
