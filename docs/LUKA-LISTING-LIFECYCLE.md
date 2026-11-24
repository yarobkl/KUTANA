# Cycle de vie des annonces

Migration appliquée : `20261124062837_luka_limit_listing_republication`.

Les annonces publiées deviennent inaccessibles au public après 30 jours grâce à la date d'expiration et aux règles d'accès existantes. Une annonce retirée reste archivée. Une remise en ligne remet à zéro sa période de visibilité. Le compte est limité à trois remises en ligne par période de 24 heures ; les tentatives concurrentes sont sérialisées.

Test transactionnel annulé : trois remises en ligne et trois archivages, nouvelle échéance à 30 jours, refus de la quatrième remise en ligne, refus d'accès à un autre propriétaire et trois événements enregistrés pendant le test. Aucune donnée de test n'a été conservée. Un test de l'interface avec des comptes réels reste à faire.
