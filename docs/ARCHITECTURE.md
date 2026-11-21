# KUTANA — socle technique v0.1

## Décisions
- iOS : SwiftUI, navigation native, SF Symbols, Dynamic Type, couleurs sémantiques.
- Android futur : Kotlin / Jetpack Compose ; **même backend**, pas de réplication entre deux bases serveur.
- Supabase : PostgreSQL + Auth + Storage + Realtime. Le schéma SQL fourni est un point de départ non déployé.
- Stockage iOS local : SwiftData pour cache et brouillons uniquement ; Keychain pour les secrets. Pas de base iCloud publique pour les annonces.
- Les prix sont stockés en entiers XAF (FCFA), jamais en flottants.
- Auth : e-mail obligatoire, lien de confirmation, session protégée ; bloquer les opérations sensibles si e-mail non confirmé.
- Notifications : APNs via backend après événement serveur confirmé, jamais directement par l'autre utilisateur.
- CV : bucket privé, URL signées à courte durée, autorisation candidat/recruteur vérifiée côté serveur.

## Sécurité avant production
1. Éviter la publication anonyme et vérifier les comptes ; mettre en place rate limiting, CAPTCHA adapté et anti-spam.
2. Créer une RPC validée pour les conversations (pas de politique d'insertion directe).
3. Créer des RPC serveur pour les transitions de statut des candidatures et l'audit des ouvertures de CV.
4. Ajouter modération, signalement, blocage, suppression de compte, rétention et politique de confidentialité.
5. Vérifier les obligations applicables au Congo (emploi, annonces, données personnelles) et les règles App Store.
6. Ajouter tests d'intégration RLS, tests UI, tests de non-régression visuelle et tests d'accessibilité.
7. Utiliser TLS et chiffrement au repos géré par l'hébergeur ; AES seul ne constitue pas une architecture de sécurité.

## Limites de cette livraison
- Écrans natifs SwiftUI démonstratifs ; données d'offres fictives explicitement indiquées.
- Pas d'authentification opérationnelle, de notifications APNs, d'upload CV ni de messagerie temps réel.
- Pas de projet .xcodeproj : créer un projet iOS SwiftUI dans Xcode et importer le dossier `iOS/KUTANA`.
- Code non compilé sur simulateur dans cet environnement ; vérifier la compilation avant intégration.
- Ne pas utiliser les coordonnées, noms ou contenus des maquettes comme données réelles.
