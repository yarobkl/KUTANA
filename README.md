# KUTANA

Application iOS native SwiftUI dédiée aux offres d'emploi et aux petites annonces au Congo-Brazzaville.

## État du projet

- Dépôt privé réservé à KUTANA.
- Backend indépendant Supabase : projet `xwhjzftrzikgqweowtus` (région Paris).
- Version locale de référence : KUTANA v0.10 (préparation du build).
- **Le code source complet n'est pas encore publié dans ce dépôt. Aucun build iOS n'a été validé à ce stade.**

## Architecture cible

- iOS : SwiftUI natif.
- Backend : base KUTANA exclusivement, PostgreSQL, authentification Supabase, RLS.
- Fonctionnalités : emploi, candidatures, annonces, messagerie privée.
- Livraison : GitHub Actions sur macOS, puis TestFlight après tests et signature.

## Isolation

Aucun lien technique avec COVI, BININGA ni l'ancien Congo Emploi.

Ne jamais publier de clé `service_role`, de clé secrète Supabase, de certificat Apple ou de jeton d'authentification.
