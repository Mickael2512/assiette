export interface Env {
  GEMINI_API_KEY: string;
  GEMINI_MODEL?: string;
  ALLOWED_ORIGINS?: string;
  AI_RATE_LIMITER: { limit: (options: { key: string }) => Promise<{ success: boolean }> };
}

const cors = (request: Request, env: Env) => {
  const origin = request.headers.get("Origin") ?? "";
  const allowed = (env.ALLOWED_ORIGINS ?? "").split(",").map(v => v.trim()).filter(Boolean);
  const headers = new Headers({
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Vary": "Origin"
  });
  if (allowed.includes(origin)) headers.set("Access-Control-Allow-Origin", origin);
  return headers;
};

const json = (body: unknown, status: number, headers: Headers) => {
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  return new Response(JSON.stringify(body), { status, headers });
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const headers = cors(request, env);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") {
      return json({ ok: true, service: "assiette-food-analysis" }, 200, headers);
    }
    if (url.pathname !== "/v1/analyze-food" || request.method !== "POST") {
      return json({ error: "Not found" }, 404, headers);
    }
    const clientIP = request.headers.get("CF-Connecting-IP") ?? "unknown";
    const rate = await env.AI_RATE_LIMITER.limit({ key: clientIP });
    if (!rate.success) return json({ error: "Trop de demandes. Réessaie dans une minute." }, 429, headers);

    if (!env.GEMINI_API_KEY) return json({ error: "AI service is not configured." }, 503, headers);

    const length = Number(request.headers.get("Content-Length") ?? "0");
    if (length > 8_000_000) return json({ error: "Image too large. Maximum 8 MB." }, 413, headers);

    let input: { imageBase64?: string; mimeType?: string; locale?: string };
    try { input = await request.json() as typeof input; }
    catch { return json({ error: "Invalid JSON body." }, 400, headers); }

    const image = input.imageBase64 ?? "";
    const mimeType = input.mimeType ?? "image/jpeg";
    if (!image || image.length > 7_500_000 || !["image/jpeg", "image/png", "image/webp"].includes(mimeType)) {
      return json({ error: "A JPEG, PNG or WebP image under 5.5 MB is required." }, 400, headers);
    }

    const prompt = `Tu es un assistant expert en analyse alimentaire pour une application de journal nutritionnel française.
Analyse la photo du repas et renvoie uniquement un JSON conforme au schéma.
Identifie d'abord le plat global (ex: lasagnes, pad thaï), puis décompose-le en ingrédients alimentaires plausibles et distincts.
Pour chaque ingrédient, estime sa masse en grammes pour la portion visible. Les masses doivent être des estimations prudentes, pas des mesures. Ne crée pas artificiellement des ingrédients invisibles : si une sauce, huile ou ingrédient caché est probable mais impossible à identifier, signale-le dans uncertainties plutôt que de l'affirmer.
Ne donne aucune calorie ni macro : elles seront calculées séparément depuis Ciqual. N'invente pas de précision. Si le plat ou la quantité est ambiguë, baisse confidence et explique pourquoi.
Langue: français. Locale: ${input.locale ?? "fr-FR"}.
Réponds avec dishName, ingredients (name, searchTerms, estimatedGrams, confidence, preparation), uncertainties et overallConfidence.
Les ingrédients doivent être atomiques et exploitables pour une recherche Ciqual (ex: nouilles de riz cuites, crevettes cuites, œuf, tofu, cacahuètes, sauce pad thaï). Ne mets pas le nom du plat comme unique ingrédient si le contenu peut être décomposé.`;

    const model = env.GEMINI_MODEL ?? "gemini-2.5-flash";
    const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
    const schema = {
      type: "OBJECT",
      properties: {
        dishName: { type: "STRING" },
        overallConfidence: { type: "NUMBER" },
        uncertainties: { type: "ARRAY", items: { type: "STRING" } },
        ingredients: {
          type: "ARRAY",
          items: {
            type: "OBJECT",
            properties: {
              name: { type: "STRING" },
              searchTerms: { type: "ARRAY", items: { type: "STRING" } },
              estimatedGrams: { type: "NUMBER" },
              confidence: { type: "NUMBER" },
              preparation: { type: "STRING" }
            },
            required: ["name", "searchTerms", "estimatedGrams", "confidence", "preparation"]
          }
        }
      },
      required: ["dishName", "overallConfidence", "uncertainties", "ingredients"]
    };

    const upstream = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [
          { text: prompt },
          { inline_data: { mime_type: mimeType, data: image } }
        ] }],
        generationConfig: {
          temperature: 0.2,
          responseMimeType: "application/json",
          responseSchema: schema,
          maxOutputTokens: 1800
        }
      })
    });

    if (!upstream.ok) {
      const raw = await upstream.text();
      let providerMessage = "Erreur du fournisseur IA.";
      try { providerMessage = JSON.parse(raw)?.error?.message ?? providerMessage; } catch {}
      providerMessage = String(providerMessage).slice(0, 500);
      console.error("gemini_provider_error", JSON.stringify({ status: upstream.status, message: providerMessage }));
      return json({ error: "Le fournisseur IA a refusé la demande.", code: "GEMINI_ERROR", providerStatus: upstream.status, providerMessage }, 502, headers);
    }
    const payload = await upstream.json() as any;
    const text = payload?.candidates?.[0]?.content?.parts?.map((p: any) => p.text ?? "").join("") ?? "";
    if (!text) {
      const reason = payload?.promptFeedback?.blockReason ?? payload?.candidates?.[0]?.finishReason ?? "EMPTY_RESPONSE";
      console.error("gemini_empty_response", String(reason));
      return json({ error: "Le service IA n'a renvoyé aucune analyse.", code: "EMPTY_AI_RESPONSE", providerMessage: String(reason) }, 502, headers);
    }

    try {
      const result = JSON.parse(text);
      if (!Array.isArray(result.ingredients) || result.ingredients.length === 0) {
        return json({ error: "No ingredients could be identified.", analysis: result }, 422, headers);
      }
      result.ingredients = result.ingredients
        .filter((item: any) => typeof item.name === "string" &&
          Number.isFinite(item.estimatedGrams) && item.estimatedGrams > 0 &&
          Number.isFinite(item.confidence))
        .slice(0, 20)
        .map((item: any) => ({
          ...item,
          estimatedGrams: Math.min(2000, Math.max(1, item.estimatedGrams)),
          confidence: Math.min(1, Math.max(0, item.confidence))
        }));
      result.overallConfidence = Math.min(1, Math.max(0, Number(result.overallConfidence) || 0));
      return json(result, 200, headers);
    } catch {
      console.error("gemini_invalid_json_response");
      return json({ error: "La réponse du service IA est inexploitable.", code: "INVALID_AI_JSON" }, 502, headers);
    }
  }
};
