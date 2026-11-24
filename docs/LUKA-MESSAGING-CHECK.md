# Vérification de la messagerie au niveau de la base

Une vérification transactionnelle a été exécutée le 23 novembre 2026 contre le projet Supabase KUTANA. Trois identités synthétiques et une annonce de test ont été créées à l'intérieur d'une transaction annulée.

Résultats : création d'une conversation acheteur-vendeur ; réutilisation de la même conversation lors d'un second appel ; envoi d'un message par chacun des deux participants ; lecture de deux messages par chacun ; absence de lecture et refus d'envoi pour une troisième identité.

Une requête après annulation a confirmé qu'aucune identité ni annonce de test ne subsistait.

Cette vérification couvre les fonctions et les politiques de base de données, pas la connexion réelle ni le parcours complet sur deux appareils iOS. Le test de bout en bout reste nécessaire.
