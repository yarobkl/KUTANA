# KUTANA — Expérience native premium (itération 1)

## Intention
L'application doit être instantanément compréhensible, réactive, accessible et digne d'une application iOS de référence. L'objectif « fluidité Uber » est un objectif d'expérience et de performance, pas une promesse de 120 images/s sans mesures sur appareil.

## Modifications SwiftUI
- `Core/Theme.swift`: langage de mouvement commun, transition douce des images, squelettes de chargement sans animation permanente, boutons avec pression discrète.
- `App/RootView.swift`: retour haptique natif sur le changement d'onglet, TabView système conservée.
- `Features/Jobs/JobsView.swift`: hiérarchie éditoriale des offres, squelettes uniquement au premier chargement, conservation du contenu lors de l'actualisation.
- `Features/Market/MarketView.swift`: navigation horizontale des catégories avec sélection tactile, galerie et miniatures à dimensions stables, fondu respectant Réduire les animations.
- `Features/Messages/MessagesView.swift`: défilement à l'arrivée de messages adapté à Réduire les animations, haptique seulement après envoi réussi.

## Principes
1. 100 % SwiftUI, aucune WebView ajoutée.
2. Pas d'animation en boucle ni de simulation de barre iOS.
3. Respect de l'accessibilité (VoiceOver, Réduire les animations, Dynamic Type).
4. Ne pas effacer les données pendant un rafraîchissement.
5. Aucun changement backend, aucun paiement et aucun changement de modèle commercial.

## Critères de validation à mesurer sur iPhone
- Navigation et gestes: aucune saccade visible ni perte de l'état de navigation.
- Chargement: squelettes immédiatement visibles; liste stable pendant rafraîchissement.
- Images: pas de saut de hauteur des cellules ni d'apparition brutale.
- Recherche et filtres: résultats rapides sur une liste réelle.
- Réseau dégradé: état d'erreur utile et possibilité de relancer sans écran blanc.
- Accessibilité: VoiceOver, tailles de police, Reduce Motion, contraste et mode sombre.
- Performance: Instruments/MetricKit sur build TestFlight (temps de démarrage, temps de réponse interaction, dropped frames, mémoire, énergie), avec objectifs chiffrés fixés **après mesure de référence**.

## Limites
Une compilation cloud ne prouve pas à elle seule la fluidité perçue sur iPhone. Le passage à une expérience « waouh » exige encore des captures simulateur, tests UX réels, audit des chargements réseau et mesures Instruments.
