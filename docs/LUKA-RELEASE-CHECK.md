# LUKA — vérifications et limites

## Partage
Le domaine `luka-partage.vercel.app` fournit les fiches des annonces et offres accessibles sans compte et des métadonnées sociales. Une annonce réelle avec photographie et prix et une offre réelle ont été consultées ; une référence absente renvoie 404. Le fichier Apple App Site Association répond en JSON. Le routage natif et les domaines associés sont implémentés dans l'application mais leur ouverture sur un iPhone signé reste à tester.

## Favoris d'annonces
Migration Supabase `20261124035237_luka_listing_favorites_account_ownership` versionnée. Les favoris sont désormais enregistrés par compte ; les anciennes données locales ne sont pas attribuées automatiquement car leur propriétaire n'est pas identifiable. Une proposition d'importation explicite est disponible.

Un test de base transactionnel annulé a vérifié qu'un utilisateur authentifié peut lire son favori et qu'une autre identité ne peut pas le lire. Le rôle anonyme n'a pas de droit SELECT. Aucune ligne de test n'a été conservée. Ceci ne constitue pas un test complet sur deux sessions iOS réelles.

## Vérification anonyme réelle

Une requête HTTP sans session a retourné l'offre publique et la liste de commentaires (vide pour l'offre contrôlée). Les profils privés, conversations, candidatures, favoris et signalements ont chacun renvoyé HTTP 401. Un test SQL transactionnel annulé a vérifié qu'une annonce expirée et ses commentaires ne sont pas publics.

## Encore à vérifier avant TestFlight
Inscription et confirmation avec une adresse réelle ; commentaires depuis l'application ; ajout et retrait des favoris sur deux sessions ; messagerie de bout en bout entre deux comptes de test ; ouverture d'un lien universel sur un iPhone signé ; captures des écrans secondaires ; signature et profil incluant les domaines associés. Google est reporté.
