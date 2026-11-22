# KUTANA — préparation TestFlight

Dernière vérification : 22 novembre 2026.

## Situation

- Dépôt privé : `yarobkl/KUTANA`.
- Bundle iOS dédié : `fr.yaroconsulting.kutana`.
- Base Supabase dédiée : `xwhjzftrzikgqweowtus` (aucune dépendance avec BININGA, COVI ou Congo Emploi).
- La compilation simulateur et l'archive iPhone **sans signature** ont réussi sur GitHub Actions.
- **Aucun build signé ni envoyé à TestFlight n'est attesté.**
- Le workflow `.github/workflows/testflight.yml` est déclenchable **manuellement uniquement** afin d'éviter tout envoi involontaire.

## Prérequis Apple

1. Compte Apple Developer actif avec droits de distribution, et fiche d'application KUTANA créée dans App Store Connect.
2. Identifiant explicite `fr.yaroconsulting.kutana` enregistré chez Apple et correspondant exactement à l'application.
3. Certificat Apple Distribution exporté en `.p12` avec sa clé privée et son mot de passe.
4. Profil d'approvisionnement **App Store Connect** non expiré, lié au même identifiant et à la même équipe Apple.
5. Clé API **d'équipe** App Store Connect (.p8), son Key ID et son Issuer ID, avec permissions pour envoyer des builds.

Ne jamais envoyer les fichiers de clés privées dans une conversation, un commit GitHub ou un fichier de configuration public.

## Secrets GitHub requis

Dans `Settings > Secrets and variables > Actions > Repository secrets` :

| Secret | Contenu |
| --- | --- |
| `KUTANA_APPLE_TEAM_ID` | Identifiant de l'équipe Apple Developer |
| `KUTANA_DISTRIBUTION_P12_BASE64` | Encodage Base64 du fichier certificat .p12 |
| `KUTANA_DISTRIBUTION_P12_PASSWORD` | Mot de passe du fichier .p12 |
| `KUTANA_APPSTORE_PROFILE_BASE64` | Encodage Base64 du fichier .mobileprovision |
| `KUTANA_ASC_API_KEY_ID` | Key ID de la clé API App Store Connect |
| `KUTANA_ASC_API_ISSUER_ID` | Issuer ID de cette clé API |
| `KUTANA_ASC_API_PRIVATE_KEY_BASE64` | Encodage Base64 du fichier AuthKey_*.p8 |

Sur macOS, encoder localement un fichier avec `base64 -i CHEMIN_DU_FICHIER | tr -d '\n'`. Ne jamais insérer le contenu décodé du .p12 ou .p8 dans le dépôt.

## Déclencher la première livraison

1. Vérifier l'enregistrement du Bundle ID et l'existence de la fiche App Store Connect.
2. Ajouter les sept secrets dans GitHub. Le workflow vérifie leur présence avant toute compilation.
3. Ouvrir `Actions > KUTANA TestFlight > Run workflow` sur la branche `main`.
4. Le workflow lance le runner `macos-26`, exige Xcode 26+, importe temporairement le certificat et le profil, génère l'archive signée, exporte une IPA puis la transmet à App Store Connect.
5. Vérifier ensuite le traitement du build et l'ajout des testeurs dans App Store Connect ; le téléchargement par les testeurs n'est pas automatique.

Les éventuels échecs de signature ou de transfert doivent être corrigés à partir des journaux de la première exécution. Ce workflow n'a pas encore été exécuté avec des identifiants Apple.

## Points restant à sécuriser avant un déploiement public

- Vérifier les six RPC `SECURITY DEFINER` signalées par les conseils de sécurité Supabase : elles peuvent être nécessaires aux transactions métier, mais chacune doit vérifier les permissions de l'utilisateur et le périmètre de ses données.
- Tester de bout en bout la création de comptes, la confirmation de l'e-mail, les sessions et les politiques RLS avec deux comptes distincts.
- Ajouter la modération, les signalements, la gestion des CV/photos, la conformité réglementaire, les textes légaux et les tests d'accessibilité.
- Valider les écrans iPhone réels par rapport aux maquettes, sans considérer un build réussi comme une validation visuelle.
