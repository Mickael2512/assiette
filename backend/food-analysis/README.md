# Assiette — service d'analyse alimentaire

Ce Worker Cloudflare est le proxy serveur entre l'app iOS et Gemini. La clé Google reste exclusivement dans le secret Cloudflare ; elle ne doit jamais être intégrée à l'IPA.

## Déploiement

1. Créer un Worker Cloudflare et installer Wrangler.
2. Depuis ce dossier : `npm install -D wrangler typescript`.
3. Définir le secret : `npx wrangler secret put GEMINI_API_KEY`.
4. Vérifier le modèle disponible dans le projet Google AI Studio, puis régler `GEMINI_MODEL` dans `wrangler.toml`.
5. Déployer : `npx wrangler deploy`.
6. Configurer dans l'app iOS l'URL `https://<worker>.<account>.workers.dev/v1/analyze-food`.

## Contrat

POST JSON :
`{ "imageBase64": "...", "mimeType": "image/jpeg", "locale": "fr-FR" }`

Réponse JSON : plat, ingrédients, poids estimés, confiance et incertitudes. Le Worker ne renvoie jamais de calories/macros : le calcul doit être effectué à partir de CIQUAL dans l'app.

## Sécurité et coûts

- La clé Gemini est un secret Worker, jamais un secret client.
- Limite de taille d'image et nombre maximal d'ingrédients.
- Avant ouverture publique, activer Cloudflare Rate Limiting/WAF et un budget/alerte côté Google. CORS n'est pas une authentification et une app iOS ne peut pas garder un secret partagé.
- Le niveau gratuit Gemini dépend du modèle, de la région et des quotas du compte ; il n'est ni illimité ni garanti. Prévoir un plafond et une réponse propre en cas de quota.
- Ne pas conserver les images ni les journaux contenant des données photo.
