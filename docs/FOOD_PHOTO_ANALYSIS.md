# Analyse photo des repas — architecture cible

## Objectif produit

Permettre à Assiette de transformer une ou plusieurs photos d'un repas composé en une proposition structurée et modifiable : aliments/ingrédients visibles, quantité estimée en grammes, nutriments calculés à partir d'une base de référence locale, et niveau d'incertitude. Le flux essentiel doit fonctionner sans compte tiers, sans clé API et sans envoyer de photo hors de l'iPhone.

L'analyse photo est une aide à la saisie, jamais une mesure exacte. Une photo 2D ne révèle pas systématiquement la profondeur, les ingrédients cachés, l'huile absorbée, les sauces ou le poids réel. L'interface ne doit donc jamais présenter une estimation comme une valeur pesée.

## Parcours utilisateur

1. L'utilisateur photographie son assiette. L'app propose une vue de dessus et, si nécessaire, une seconde vue oblique. Une capture supplémentaire est demandée uniquement si elle peut réduire une incertitude importante.
2. Le moteur repère le plat et les régions alimentaires, puis propose plusieurs ingrédients avec masques/boîtes et scores de confiance.
3. Le moteur estime les portions. Il exploite la géométrie de l'assiette ou un objet de référence lorsque disponible. La profondeur ARKit/RoomPlan/sceneDepth est un bonus sur les appareils compatibles, jamais une dépendance.
4. Assiette associe chaque ingrédient à un aliment CIQUAL local, en tenant compte de l'état (cru/cuit), de la préparation et des variantes pertinentes.
5. L'utilisateur corrige les ingrédients, la préparation et les grammes. Les huiles, sauces et ingrédients non visibles sont explicitement demandés lorsque leur impact est significatif.
6. L'app calcule les nutriments à partir des valeurs par 100 g et des quantités validées, puis enregistre le repas avec la provenance et le caractère estimé des données.

## Architecture technique iOS

### A. Capture

- SwiftUI pour le parcours et les écrans de correction.
- AVFoundation pour capturer des images nettes et conserver les métadonnées utiles.
- Captures multiples facultatives, guidées et liées à la même session de repas.
- Traitement des images en mémoire ; ne pas journaliser ni téléverser les photos.
- Gestion explicite des autorisations caméra et de la disponibilité matérielle.

### B. Vision et segmentation

Le classifieur Vision générique actuellement présent dans `Databases.swift` est uniquement un prototype de suggestion. Il ne constitue pas un moteur de décomposition d'assiette.

Le moteur cible doit combiner :
- détection multi-objets / multi-aliments ;
- segmentation par instance ou segmentation sémantique afin de délimiter les composants ;
- reconnaissance spécialisée des aliments et des préparations ;
- fusion des résultats de plusieurs vues.

Les modèles doivent être exécutables localement via Core ML / Vision, quantifiés si la qualité reste acceptable, et évalués sur des repas réellement photographiés avec une cuisine française/européenne représentative. Aucun modèle ne sera embarqué avant audit de licence, provenance des poids et droits sur les données d'entraînement.

### C. Estimation des portions

Ne jamais déduire des grammes d'un simple score de classification.

Combiner, selon la disponibilité :
- aire du masque et géométrie apparente ;
- dimension connue de l'assiette ou objet de référence ;
- seconde vue pour réduire les ambiguïtés de volume ;
- profondeur/mesure spatiale ARKit sur les seuls appareils compatibles ;
- modèles statistiques calibrés par famille d'aliments et préparation.

Chaque portion doit conserver une estimation centrale et une plage plausible ou un indicateur de confiance. Si l'incertitude est trop grande, demander une correction de quantité ou une précision à l'utilisateur au lieu d'inventer une précision.

### D. Moteur nutritionnel local

- CIQUAL est la source de référence prioritaire pour les aliments génériques et les préparations courantes en France.
- Stocker les données nutritionnelles utiles localement et documenter la version/source de la base.
- Open Food Facts peut compléter les produits emballés, mais ses données communautaires ne doivent pas être traitées comme équivalentes à une mesure de laboratoire.
- Calculer les nutriments par quantité uniquement lorsque la valeur correspondante est connue.
- Une valeur absente doit rester inconnue, jamais être convertie silencieusement en zéro.
- Conserver la source de chaque aliment et distinguer poids saisi, poids mesuré et poids estimé.

### E. Modèle de données

Une ligne d'ingrédient issue d'une analyse doit au minimum conserver :
- identifiant de l'aliment CIQUAL (ou source alternative) ;
- nom affiché et préparation ;
- quantité en grammes ;
- provenance de la quantité (saisie, pesée, estimation photo) ;
- confiance/plage d'estimation ;
- valeurs nutritionnelles disponibles et complétude ;
- identifiant de session/photo pour relier les corrections sans conserver l'image si elle n'est pas nécessaire.

Les anciennes sauvegardes doivent rester lisibles. Les migrations ne doivent pas convertir les nutriments absents en zéros réels.

## Évaluation obligatoire avant toute promesse marketing

Créer un jeu de validation de repas pesés individuellement, avec recettes, ingrédients, masses, méthodes de cuisson et photos multi-angles. Inclure des plats composés, sauces, huiles, aliments superposés et portions variées.

Mesurer séparément :
- précision/rappel/F1 par ingrédient ;
- qualité des masques (IoU) ;
- erreur absolue moyenne des masses (g), par ingrédient et par repas ;
- erreur kcal et macros par repas ;
- taux de corrections utilisateur ;
- latence, mémoire, taille des modèles et consommation énergétique sur plusieurs générations d'iPhone.

Nutrition5k est une piste de recherche/benchmark utile car il associe images et mesures de masse/nutrition, mais son origine et son éventail de plats ne suffisent pas à valider seuls une expérience française. Il faudra un jeu complémentaire local et des tests en conditions réelles.

Aucune équivalence avec Yazio ne doit être revendiquée avant comparaison reproductible sur un protocole identique.

## Politique de sélection des modèles et licences

- Refuser les modèles/données avec licence non commerciale ou obligations incompatibles avec la distribution prévue.
- Ne pas intégrer un modèle AGPL dans l'application sans décision juridique explicite sur les conséquences pour le projet.
- Vérifier séparément la licence du code, des poids, des datasets et des éventuels composants de pré/post-traitement.
- Préférer un modèle Core ML compact et spécialisé, mais ne pas sacrifier la segmentation ou l'estimation des masses à un simple classifieur rapide.
- Les modèles lourds peuvent être proposés en téléchargement optionnel ultérieur, mais le parcours de base doit rester utilisable hors ligne sans compte.

## Découpage de réalisation

1. **Fiabiliser les données** : nutriments optionnels/complets, unités, sources, migration et calcul nutritionnel.
2. **Définir le contrat d'analyse** : ingrédients, masques, quantités, incertitudes, préparation et erreurs explicites.
3. **Évaluer les modèles candidats** : licences, Core ML, performances sur appareil, qualité sur repas composés.
4. **Construire le pipeline photo** : capture multi-vues, détection, segmentation et fusion.
5. **Construire l'estimation de portions** : calibration, références visuelles, profondeur facultative et intervalles.
6. **Créer l'écran de validation** : modifier/supprimer/ajouter un ingrédient, régler les grammes, renseigner huile/sauce/cuisson.
7. **Constituer le benchmark et publier les métriques** avant de considérer la fonction comme prête.

## Critères d'acceptation

- Une analyse photo ne nécessite aucun compte, aucune clé API et aucune connexion.
- Les photos ne quittent jamais l'appareil dans le parcours standard.
- Un plat composé peut produire plusieurs ingrédients indépendants, chacun corrigeable.
- Les grammes sont explicitement marqués comme estimés tant qu'ils ne sont pas pesés/saisis.
- Les valeurs nutritionnelles inconnues restent inconnues.
- L'utilisateur valide le résultat avant son ajout au journal.
- Les performances et erreurs sont mesurées sur des repas pesés ; aucune précision non démontrée n'est affichée.
