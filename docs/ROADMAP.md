# KUTANA — état v0.3

## Réalisé dans le code source
- Structure SwiftUI native existante (Emploi, Annonces, Publier, Messages, Profil).
- Modèles de domaine et client REST de lecture.
- Nouveau service Auth REST (inscription, connexion, récupération) ; intégration UI et persistance de session encore à faire.
- Migrations SQL 001–003 (schéma, RLS, RPC et contraintes).
- Document d'isolation stricte.

## À terminer avant TestFlight
- Provisionner un nouveau Supabase KUTANA et exécuter les migrations après revue.
- Corriger et tester les RPC sous PostgreSQL, en particulier concurrence et permissions.
- Relier AuthService aux écrans d'inscription et confirmation, stocker les sessions en Keychain et gérer le refresh.
- CRUD de publication avec validation serveur, CV/photos avec stockage privé et URLs temporaires.
- Messagerie temps réel, modération et signalement, notifications APNs via serveur.
- Générer projet Xcode, compiler et exécuter les tests UI sur simulateur et appareil.
- Finaliser design system, accessibilité, états d'erreur et textes légaux.

Aucune ressource cloud n'a été créée ou modifiée par cette archive.
