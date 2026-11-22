# KUTANA — iOS

Application mobile native SwiftUI conçue pour les offres d'emploi et les petites annonces au Congo-Brazzaville. Ce dépôt est **indépendant** de COVI, BININGA et de l'ancien Congo Emploi.

## Organisation

- `iOS/KUTANA/` : application iOS, interface SwiftUI, domaine, authentification et réseau.
- `project.yml` : génération du projet Xcode avec XcodeGen ; bundle ID `fr.yaroconsulting.kutana`.
- `Tests/` : tests Swift de domaine, réseau/authentification, brouillons et messagerie.
- `supabase/migrations/` : schéma SQL et politiques de sécurité du **projet Supabase KUTANA uniquement**.
- `.github/workflows/ios-build.yml` : pipeline de compilation pour simulateur iOS sur macOS, sans signature.
- `docs/` : notes d'architecture, état d'avancement et références de design.

## État vérifié

- Les quatre suites de tests Swift passent en local (environnement Linux).
- Le backend dédié Supabase KUTANA existe et ses neuf migrations ont déjà été appliquées.
- La compilation simulateur et l'archive Release pour iPhone **sans signature** ont réussi sur GitHub Actions (21 novembre 2026). Le fonctionnement sur un iPhone physique reste à vérifier.
- Les archives actuelles **ne sont pas des builds TestFlight**. Le workflow manuel `.github/workflows/testflight.yml` prépare la signature, l'export IPA et l'envoi, après configuration des sept secrets Apple (voir `docs/TESTFLIGHT-SETUP.md`). Il n'a pas encore été lancé avec les certificats.
- Les maquettes approuvées n'ont pas encore été contrôlées au pixel près sur simulateur.

## Distribution TestFlight

Le pipeline de distribution est volontairement manuel. Les identifiants Apple doivent être enregistrés exclusivement dans les secrets GitHub, jamais dans le dépôt. Lire [le guide de préparation TestFlight](docs/TESTFLIGHT-SETUP.md) avant de lancer le workflow.

## Lancer les tests localement

```bash
bash Tests/run-smoke.sh
```

Sur un Mac équipé d'Xcode et de XcodeGen :

```bash
xcodegen generate
xcodebuild -project KUTANA.xcodeproj -scheme KUTANA -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Confidentialité

Seule la clé **publique** Supabase est utilisée par l'application. Ne jamais commiter de jetons Apple, `.p8`, certificats, secrets de service ou fichiers `.env` privés. Les données du serveur appartiennent exclusivement à KUTANA.
