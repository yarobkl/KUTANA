# KUTANA 0.7 — état des corrections

- Tests exécutés : `Tests/run-smoke.sh` sous Swift 6.2.1 Linux.
- Domaine : OK.
- Authentification et transport (réponses simulées) : OK.
- Validation métier et RPC de brouillons (réponses simulées) : OK.
- Parseur Swift sur l’ensemble du dossier iOS : OK.
- Xcode, Figma, TestFlight : non testés, non modifiés.
- Supabase : création refusée pour limite du forfait gratuit, aucune migration appliquée.

Avant toute mise en production : confirmer les messages d’erreur HTTP, l’e-mail de validation, l’accessibilité et le support clavier ; contrôler la RLS avec plusieurs comptes de test ; ajouter un mécanisme de modération et d’administration séparée ; vérifier la conformité de la maquette graphique approuvée.
