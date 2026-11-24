# Tester Assiette dans LiveContainer

## IPA attendue

Le workflow GitHub Actions « Build IPA » compile l'application iOS sans signature Apple de distribution, puis archive `Payload/Assiette.app` dans `Assiette.ipa`. LiveContainer doit pouvoir re-signer l'application invitée avec le certificat importé depuis AltStore ou SideStore en mode JIT-less.

Le build doit être vert avant de télécharger l'artefact. Ne pas utiliser une archive issue d'un run échoué ou incomplet.

## Prérequis LiveContainer

- Utiliser uniquement une version officielle de LiveContainer publiée par le projet.
- Installer LiveContainer avec AltStore 2.2.1+ ou SideStore 0.6.2+.
- Dans LiveContainer > Settings, importer le certificat depuis AltStore/SideStore.
- Lancer « JIT-Less Mode Diagnose » puis « Test JIT-Less Mode ».
- Vérifier que le diagnostic affiche « JIT-Less Mode Test Passed ».

LiveContainer documente iOS/iPadOS 15+ comme prérequis. Le mode JIT-less permet de lancer les apps invitées sans activer JIT ; Assiette ne doit pas nécessiter JIT.

## Installer Assiette

1. Télécharger `Assiette-ipa` depuis l'onglet Actions du dépôt, dans le run « Build IPA » réussi.
2. Extraire `Assiette.ipa` du ZIP de l'artefact si GitHub a fourni l'artefact sous forme d'archive.
3. Transférer le fichier IPA vers l'iPhone (Fichiers, AirDrop ou partage).
4. Ouvrir LiveContainer, toucher le bouton `+`, puis choisir le fichier IPA.
5. Sélectionner Assiette et la lancer.
6. Si LiveContainer demande une signature, vérifier à nouveau le certificat et le diagnostic JIT-less.

## Première batterie de tests

- Ouvrir chaque onglet et vérifier l'absence de fermeture inattendue.
- Ajouter un aliment manuellement, fermer l'app, la rouvrir et vérifier la persistance.
- Importer le CSV CIQUAL puis rechercher un aliment en mode hors ligne.
- Tester une photo depuis la photothèque puis la caméra ; vérifier que l'analyse reste locale.
- Tester l'autorisation caméra et le refus d'autorisation.
- Vérifier l'édition des quantités, les totaux et l'historique.
- Tester le sélecteur de fichiers dans LiveContainer. Si le sélecteur ne renvoie pas de fichier, activer « Fix File Picker » dans les réglages propres à Assiette.
- Signaler les erreurs avec le modèle d'iPhone, version iOS, version LiveContainer, écran concerné et étapes pour reproduire.

## Limites connues de la version prototype

La reconnaissance Vision actuellement embarquée ne décompose pas correctement un plat composé et n'estime pas la masse. Elle ne doit pas être évaluée comme la future fonctionnalité photo. Le test sert d'abord à valider le démarrage, les écrans, les sauvegardes, les permissions, le parcours CIQUAL et le packaging LiveContainer.

Aucun test de compilation ou de lancement sur appareil ne doit être déclaré réussi avant confirmation effective sur GitHub Actions et sur l'iPhone.
