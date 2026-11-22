# KUTANA — Livraison interne iOS (22 novembre 2026)

## Périmètre exécuté
Application native SwiftUI, bundle `fr.yaroconsulting.kutana`, dépôt indépendant `yarobkl/KUTANA`, backend dédié Supabase `xwhjzftrzikgqweowtus`. Aucune ressource COVI, BININGA ou Congo Emploi réutilisée.

### Publication et petites annonces
- Brouillons persistants visibles dans « Mes publications », passage explicite en ligne et retrait. Aucun brouillon existant ne devient public automatiquement.
- Authentification, contrôle serveur de propriété, confirmation d’e-mail et limite quotidienne sur les publications.
- Une annonce ne devient publique qu’après l’ajout d’au moins une image JPEG (jusqu’à cinq).
- Recherche par texte et catégorie, galerie/photo dans les fiches, démarrage d’une conversation vendeur privée et signalement du contenu.

### Emploi
- Candidature aux offres publiées avec suivi du statut.
- Liste des candidatures reçues réservée au recruteur ayant créé l’offre.
- Changement de statut avec RPC vérifiée et journal existant; conversation candidat/recruteur.
- Import d’un CV PDF privé jusqu’à 5 Mo depuis Fichiers, consultation autorisée candidat/recruteur dans Quick Look.

### Vérifications techniques
- SQL `010_publication_and_reporting` → `013_private_application_cvs` appliquées sur la base dédiée.
- Comptage avant livraison: 1 offre en brouillon + 1 annonce en brouillon; 0 publication automatique.
- Contrôle des grants: pas d’exécution publique des RPC sensibles.
- Tests Swift `publications_smoke.swift` (HTTP simulé): publication, retrait, candidatures reçues, changement de statut, conversations, signalements, photos, CV.
- GitHub Actions macOS: compiler et confirmer les tests + le simulateur avant fusion. Tests HTTP simulés != validation réelle avec des comptes et JWT distincts.

## Ce qui reste avant ouverture publique
**Ne pas présenter cette version comme prête pour tous les utilisateurs :**
1. Validation fonctionnelle multi-comptes sur iPhone via TestFlight (candidat, recruteur, vendeur, acheteur) et vérifications RLS end-to-end.
2. Modération opérationnelle des signalements et des annonces à risque, protections antispam/stockage et procédure de signalement/traitement.
3. Gestion complète du compte (suppression de compte depuis l’app et dépendances de données), confidentialité, CGU, politique de rétention/conformité locale.
4. Test d’accessibilité et d’interface par rapport aux maquettes, notifications de messages/candidatures, possibilité de modifier un brouillon existant.
5. Auth Supabase: activer protection contre mots de passe compromis (Alerte Security Advisor), évaluer toutes les RPC SECURITY DEFINER publiques avec un audit de permissions.
6. Vérifier les écrans d’App Store Review, les données de confidentialité, la signalétique et la disponibilité réelle du build après le traitement Apple.

## Livraison
La fusion de la PR fait évoluer le dépôt main. **Elle ne garantit pas automatiquement une nouvelle build TestFlight** : le workflow de signature interne exige un déclenchement spécifique et la confirmation du traitement par Apple. Ne pas publier sur l’App Store public sans accord explicite.
