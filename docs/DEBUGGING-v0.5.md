# KUTANA v0.5 · Correctifs vérifiables

## Correctifs

- Le splash approuvé fait maintenant partie de la séquence réelle de démarrage (950 ms), avant l’onboarding ou la connexion.
- « Passer » enregistre l’onboarding terminé, comme « Commencer », pour éviter de le réafficher à chaque lancement.
- Le décodage des horodatages Supabase accepte ceux avec ou sans fractions de secondes et renvoie une erreur explicite sur les valeurs invalides.

## Tests effectués

- Vérification des modèles métier Swift et du client réseau hors iOS (swiftc -typecheck).
- Test des deux formats d’horodatage utilisés par le décodeur (fractionnaire et standard).

## Encore à vérifier

- `xcodebuild` sur runner macOS via GitHub Actions : compilation iOS non vérifiée dans ce conteneur Linux.
- Parcours iPhone, boutons, clavier, tailles dynamiques et accessibilité.
- Backend Supabase KUTANA neuf et secret publishable key : non créés/non renseignés.
- Authentification, stockage CV et notifications : non opérationnels.
- Figma : quota API Starter atteint ; aucune modification Figma sur cette itération.
- Chrome : onglets détectés, actions de clic non exposées par le connecteur Browser dans cette conversation.

**Isolation :** n’utiliser aucun projet, dépôt, base ou secret de COVI ni Congo Emploi.
