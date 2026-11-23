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


## Évaluation de modèles — état du 23 novembre 2026

### Candidat étudié : FoodSAM

FoodSAM est le candidat de recherche le plus proche du besoin fonctionnel : son approche combine un segmenter sémantique spécialisé, SAM pour produire des masques d'instances et un détecteur d'objets. Le dépôt annonce des résultats sur FoodSeg103 et UECFoodPixComplete et indique une licence Apache 2.0 pour le modèle. Le dépôt officiel reste toutefois une implémentation PyTorch orientée recherche, avec plusieurs checkpoints séparés, PyTorch 1.8.1, CUDA 11.1, MMCV et Segment Anything. Il ne fournit pas un paquet Core ML iOS prêt à intégrer. Une conversion directe sans mesure de qualité, sans vérification de chaque poids et sans test de mémoire/latence iPhone serait prématurée.

Sources consultées :
- FoodSAM, dépôt officiel et licence du modèle : https://github.com/jamesjg/FoodSAM
- Installation et dépendances/checkpoints : https://github.com/jamesjg/FoodSAM/blob/main/installation.md
- FoodSeg103 : https://github.com/ada-yl325/FoodSeg103

### Données d'entraînement

FoodSeg103 contient 7 118 images annotées au niveau pixel pour 103 catégories d'ingrédients. Attention : la licence Apache 2.0 du dépôt logiciel/benchmark ne doit pas être confondue avec les droits sur les images. Les fiches de distribution indiquent que les images proviennent de Recipe1M, dont les conditions sont réservées à la recherche/éducation non commerciale, avec accès soumis à inscription et sans redistribution générale. Ce jeu ne peut donc pas être supposé utilisable pour entraîner un modèle destiné à une application commerciale distribuée. Il peut servir de benchmark de recherche sous réserve de ses conditions d'accès, mais Assiette doit utiliser des données dont les droits autorisent explicitement l'entraînement et la redistribution commerciale.

### Décision d'intégration

FoodSAM est retenu comme candidat de prototypage et de conversion, pas comme dépendance embarquée validée. Aucun poids n'est ajouté à l'application à ce stade : nous n'avons pas encore de binaire Core ML reproductible, de mesures sur appareil ni de benchmark de masse. Le classifieur Vision actuel reste explicitement un prototype de suggestions. Il ne doit pas être présenté comme une décomposition automatique de plat.

### Étapes techniques avant activation

1. Récupérer les checkpoints depuis les sources officielles et archiver leurs empreintes SHA-256 et licences.
2. Vérifier la compatibilité des dépendances et la provenance de chaque composant tiers (notamment SAM, MMCV et le détecteur).
3. Exporter d'abord le segmenter sémantique seul vers Core ML, puis mesurer taille, précision, mémoire et latence sur plusieurs iPhone.
4. Comparer les masques au jeu de validation FoodSeg103 et à un jeu complémentaire de repas français pesés.
5. Ajouter la détection d'instances seulement si elle améliore réellement la séparation des aliments composés.
6. Développer séparément l'estimation de masse : la segmentation 2D seule ne fournit pas un poids en grammes.
7. N'activer l'expérience utilisateur qu'après validation des résultats, de la licence et du parcours de correction.


## Correction de l'audit de licence

La licence Apache 2.0 du code/benchmark FoodSeg103 ne concède pas automatiquement les droits sur les images Recipe1M. Les conditions de Recipe1M mentionnées dans les fiches du jeu imposent des limites non commerciales et d'accès/redistribution. FoodSeg103 ne doit donc pas être considéré comme une source d'entraînement librement réutilisable pour fabriquer les poids commerciaux d'Assiette. FoodSAM reste un candidat d'architecture et son dépôt annonce Apache 2.0 pour le modèle, mais chaque checkpoint et dépendance doit être contrôlé séparément. La voie la plus sûre est de constituer/obtenir un dataset dont les licences des images, annotations et modèles autorisent explicitement l'entraînement et la redistribution commerciale.

Sources :
- Dépôt officiel FoodSeg103 et licence du code : https://github.com/LARC-CMU-SMU/FoodSeg103-Benchmark-v1
- Distinction de licence entre annotations et images Recipe1M : https://huggingface.co/datasets/pictograph/foodseg103
- FoodSAM et licence annoncée pour le modèle : https://github.com/jamesjg/FoodSAM
