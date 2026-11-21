# KUTANA · Vérifications techniques v0.6

## Réalisé sur sources réelles

- Connexion via Supabase Auth REST, vérification de la longueur du mot de passe à l'inscription, confirmation e-mail obligatoire côté produit.
- Session utilisateur sauvegardée en Keychain, restauration et renouvellement si expirée ; déconnexion locale.
- Profil automatique à la création d'un compte dans `004_signup_profile_and_policy.sql`.
- Offres d'emploi et annonces chargées depuis le nouveau backend lorsque configuré ; états de chargement, absence de données et erreur.
- Candidature via RPC sécurisée `apply_to_job` et suivi des candidatures par statut.
- Assets d'icône iOS ajoutés pour permettre la génération du projet. **Icône provisoire** : remplacer par le logo vectoriel KUTANA validé avant publication.
- Séparation des environnements : aucun identifiant Supabase/GitHub de COVI ou Congo Emploi.

## Contrôles exécutables

```sh
swiftc -frontend -parse $(find iOS -name '*.swift')
swiftc -parse-as-library iOS/KUTANA/Core/Domain/Models.swift Tests/domain_smoke.swift -o /tmp/kutana-domain && /tmp/kutana-domain
swiftc -parse-as-library iOS/KUTANA/Core/Domain/Models.swift iOS/KUTANA/Core/Networking/Backend.swift iOS/KUTANA/Core/Networking/AuthService.swift Tests/network_smoke.swift -o /tmp/kutana-network && /tmp/kutana-network
```

## Non validé

- Aucun projet Supabase **KUTANA** provisionné, aucune migration appliquée, aucun test SQL réel ou authentification réseau de bout en bout.
- `xcodebuild` non exécuté ici (environnement Linux), workflow GitHub Actions non lancé.
- Figma : quota d'API Starter atteint ; aucune nouvelle modification Figma dans cette version.
- Apple et Google OAuth : boutons volontairement désactivés tant que les fournisseurs et redirections ne sont pas configurés.
- Système d'upload de CV privé, messagerie annonces, notifications push, modération et suppression de compte : à réaliser.

## Configuration de mise en service

1. Choisir l'organisation, créer un **nouveau** projet Supabase nommé KUTANA, distinct de l'ancien Congo Emploi.
2. Appliquer `001` à `005` **uniquement sur ce projet** après validation des politiques ; activer confirmation obligatoire des adresses e-mail.
3. Définir les paramètres de compilation Xcode `KUTANA_SUPABASE_URL` et `KUTANA_SUPABASE_PUBLISHABLE_KEY` (jamais de service_role côté iPhone).
4. Créer un dépôt **privé** KUTANA, y pousser uniquement cette arborescence, lancer le workflow GitHub Actions sur `main` ; corriger toute erreur Xcode réelle.
5. Vérifier sur simulateur puis iPhone physique, notamment session expirée, clavier, Dynamic Type, erreurs réseau et droits d'accès.
