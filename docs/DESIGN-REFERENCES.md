# KUTANA — références visuelles verrouillées

Les 8 écrans de référence sont **des maquettes approuvées**, pas des captures d'une app compilée.

- Référence d'ouverture : `design-reference-onboarding.png` (4 écrans : splash, présentation, connexion, inscription). La carte Emploi contient un professionnel fictif au bureau. Cette image doit être importée comme asset `kutana_employee` depuis une photographie autonome autorisée ; **ne pas découper la maquette entière pour en faire une interface**.
- Référence principale : `design-reference-core.png` (4 écrans : recherche d'emploi, détail, profil, conversation).
- Dimensions : 393 × 852 points de référence ; mise en page SwiftUI adaptative.
- Identité : bleu #2563EB, texte bleu nuit, fond blanc. Logo K bleu approuvé.
- Les noms et messages figurant sur la maquette sont fictifs et ne doivent pas être considérés comme des données réelles.

Le fichier Figma créé précédemment contient 4 écrans éditables simplifiés. Les 4 écrans principaux n'y ont pas encore été ajoutés, faute d'accès MCP (limite du forfait Starter). La reproduction pixel par pixel exige une passe visuelle dans Figma et un build iOS.

## Contrat fonctionnel
- La première ouverture affiche l'introduction, les suivantes l'écran de connexion.
- L'accès « Prévisualiser » affiche l'interface actuelle de démonstration sans simuler une session authentifiée.
- Connexion, inscription, Apple/Google et réinitialisation restent volontairement désactivées jusqu'à la configuration du backend KUTANA dédié.
- Aucune connexion ni réutilisation de COVI ou de Congo Emploi.

Asset provisoire : `Resources/Assets.xcassets/kutana_employee.imageset` contient un recadrage de la **maquette générée**, pour éviter une image manquante au lancement. Il faudra le remplacer par une photographie autonome autorisée et non par une capture de l'interface avant publication.
