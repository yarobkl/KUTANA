# Profil privé LUKA

Migration Supabase appliquée : `20261123215100_luka_private_profile_details`.

La table contenant nom, prénom, date de naissance, téléphone et localisation est accessible uniquement à son propriétaire authentifié. Un recruteur ne peut recevoir que la localisation et uniquement pour une candidature à sa propre offre lorsque le candidat a activé le consentement. Le téléphone et la date de naissance ne sont pas exposés par cette fonction.

Vérifications transactionnelles annulées avant et après application : accès du propriétaire, refus de lecture du recruteur sur la table privée, absence de localisation sans consentement, localisation consentie pour le recruteur associé, refus pour un tiers et absence de droit anonyme. Aucune donnée synthétique n'a été conservée.

L'interface de complétion et l'intégration au répertoire de migrations via le processus CLI restent à terminer.

```sql
CREATE TABLE public.luka_private_profiles (
 user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
 first_name text NOT NULL CHECK (char_length(btrim(first_name)) BETWEEN 1 AND 80),
 last_name text NOT NULL CHECK (char_length(btrim(last_name)) BETWEEN 1 AND 80),
 birth_date date NOT NULL CHECK (birth_date > DATE '1900-01-01' AND birth_date <= CURRENT_DATE),
 phone_e164 text NOT NULL CHECK (phone_e164 ~ '^\+[1-9][0-9]{7,14}$'),
 phone_region text NOT NULL CHECK (phone_region ~ '^[A-Z]{2}$'),
 country_code text NOT NULL CHECK (country_code ~ '^[A-Z]{2}$'),
 city text NOT NULL CHECK (char_length(btrim(city)) BETWEEN 1 AND 120),
 commune text NOT NULL CHECK (char_length(btrim(commune)) BETWEEN 1 AND 120),
 share_location_with_recruiters boolean NOT NULL DEFAULT false,
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.luka_private_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.luka_private_profiles FROM PUBLIC,anon,authenticated;
GRANT SELECT,INSERT,UPDATE ON public.luka_private_profiles TO authenticated;
GRANT ALL ON public.luka_private_profiles TO service_role;
CREATE POLICY "own private profile read" ON public.luka_private_profiles FOR SELECT TO authenticated
 USING (user_id=(SELECT auth.uid()));
CREATE POLICY "own private profile insert" ON public.luka_private_profiles FOR INSERT TO authenticated
 WITH CHECK (user_id=(SELECT auth.uid()));
CREATE POLICY "own private profile update" ON public.luka_private_profiles FOR UPDATE TO authenticated
 USING (user_id=(SELECT auth.uid())) WITH CHECK (user_id=(SELECT auth.uid()));
CREATE OR REPLACE FUNCTION public.luka_application_location(p_application uuid)
RETURNS TABLE(country_code text,city text,commune text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $body$
 SELECT p.country_code,p.city,p.commune
 FROM public.applications a
 JOIN public.jobs j ON j.id=a.job_id
 JOIN public.luka_private_profiles p ON p.user_id=a.candidate_id
 WHERE a.id=p_application AND j.author_id=auth.uid()
   AND p.share_location_with_recruiters=true
$body$;
REVOKE ALL ON FUNCTION public.luka_application_location(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.luka_application_location(uuid) TO authenticated;
```
