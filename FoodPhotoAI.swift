import Foundation
import UIKit

struct FoodPhotoAnalysis: Decodable {
    struct Ingredient: Decodable {
        let name: String
        let searchTerms: [String]
        let estimatedGrams: Double
        let confidence: Double
        let preparation: String
    }
    let dishName: String
    let overallConfidence: Double
    let uncertainties: [String]
    let ingredients: [Ingredient]
}

enum FoodPhotoAI {
    static func analyze(_ image: UIImage) async throws -> FoodPhotoAnalysis {
        guard let endpointString = Bundle.main.object(forInfoDictionaryKey: "ASSIETTE_FOOD_AI_URL") as? String,
              let endpoint = URL(string: endpointString),
              endpoint.scheme == "https" else {
            throw AIError.bad("Le service d’analyse photo n’est pas encore configuré. L’URL du backend doit être ajoutée à la configuration de l’app.")
        }
        guard let data = image.jpegData(compressionQuality: 0.78) else {
            throw AIError.bad("Impossible de préparer cette photo.")
        }
        guard data.count <= 5_500_000 else {
            throw AIError.bad("La photo est trop volumineuse. Choisissez une image plus légère.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "imageBase64": data.base64EncodedString(),
            "mimeType": "image/jpeg",
            "locale": Locale.current.identifier
        ])

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIError.bad("Réponse invalide du service d’analyse.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: responseData) as? [String: Any])?["error"] as? String
            if http.statusCode == 429 || http.statusCode == 502 || http.statusCode == 503 {
                throw AIError.bad("Le service d’analyse est momentanément indisponible ou a atteint son quota. Réessayez plus tard.")
            }
            throw AIError.bad(message ?? "L’analyse du plat a échoué (HTTP \(http.statusCode)).")
        }
        do {
            let result = try JSONDecoder().decode(FoodPhotoAnalysis.self, from: responseData)
            guard !result.ingredients.isEmpty else {
                throw AIError.bad("L’IA n’a pas réussi à identifier les ingrédients de ce plat.")
            }
            return result
        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.bad("La réponse du service d’analyse est inexploitable.")
        }
    }
}
