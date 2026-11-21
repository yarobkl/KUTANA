# Déploiement Supabase KUTANA — 21 novembre 2026

## Projet exact
- Nom : `kutana`
- Projet Supabase : `xwhjzftrzikgqweowtus`
- Région : `eu-west-3` (Paris)
- API : `https://xwhjzftrzikgqweowtus.supabase.co`
- État avant et pendant l'installation : `ACTIVE_HEALTHY`

## Exécuté et vérifié
- Migrations `001_initial`, `002_security_and_workflows`, `003_integrity`, `004_signup_profile_and_policy`, `005_apply_to_job`, `006_private_draft_creation`, `007_least_privilege`, `008_rpc_security` : réponses de migration `success:true` et présence confirmée dans l'historique Supabase.
- Tables métier : `profiles`, `jobs`, `applications`, `listings`, `conversations`, `messages`, `application_events`.
- Audit des permissions : RLS activée sur les sept tables.
- `anon` peut consulter uniquement `jobs` et `listings` (leurs politiques RLS filtrent les statuts publiés). Aucun accès direct en lecture aux données privées de comptes et conversations.
- `authenticated` n'a pas d'autorisation `DELETE` ou `TRUNCATE` sur les sept tables et n'a pas d'autorisation directe `INSERT`/`UPDATE` sur `jobs`/`listings`.
- RPC métier `apply_to_job`, `change_application_status`, `create_job_draft`, `create_listing_draft`, `start_application_conversation` : accès pour `authenticated` uniquement; `anon` est refusé.
- Fonctions internes `kutana_create_profile` et `guard_owner_fields` : pas d'exécution directe pour `anon`/`authenticated`.
- `project.yml` : identifiants publics client KUTANA configurés. Ne jamais utiliser la clé `service_role` dans SwiftUI.
- Tests Swift `Tests/run-smoke.sh` : 3 suites réussies.

## Ce qui n'a pas encore été prouvé
- Auth / confirmation des e-mails : nécessite activation et vérification de la configuration du projet, puis des comptes de test.
- Tests RLS de bout en bout : à faire avec deux comptes réels de test et des JWT distincts.
- OAuth Apple / Google : non configuré.
- Envoi de notification APNs, modération, mise en ligne publique, photos des annonces, CV et gestion du stockage : non prêts.
- Compilation Xcode macOS, signature, TestFlight et performance de l'app sur iPhone : non exécutés.
- Figma : création d'écrans précédemment réalisée mais fidélité exacte non validée; quota Figma rencontré.

## Isolation
BININGA (Supabase) est en pause sur demande du propriétaire. Aucun appel à ses ressources depuis KUTANA; ni COVI ni l'ancien Congo Emploi ne sont utilisés.
