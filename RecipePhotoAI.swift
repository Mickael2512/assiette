import Foundation
import UIKit
import Vision

enum RecipePhotoAI {
    static func analyze(_ image: UIImage) async throws -> RecipeDTO {
        guard let cgImage = image.cgImage else { throw AIError.bad("Impossible de lire cette photo.") }
        let recognizedText: String = try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["fr-FR", "en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.008
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
        let cleaned = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 40 else { throw AIError.bad("Je n’arrive pas à lire suffisamment de texte. Reprenez la photo bien à plat, avec davantage de lumière.") }
        guard let base = Bundle.main.object(forInfoDictionaryKey: "ASSIETTE_FOOD_AI_URL") as? String,
              var components = URLComponents(string: base), components.scheme == "https" else {
            throw AIError.bad("Le service d’import de recettes n’est pas configuré.")
        }
        components.path = "/v1/parse-recipe"
        guard let url = components.url else { throw AIError.bad("Adresse du service invalide.") }
        var requestAPI = URLRequest(url: url)
        requestAPI.httpMethod = "POST"
        requestAPI.timeoutInterval = 60
        requestAPI.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requestAPI.httpBody = try JSONSerialization.data(withJSONObject: ["text": String(cleaned.prefix(14000)), "locale": Locale.current.identifier])
        let (data, response) = try await URLSession.shared.data(for: requestAPI)
        guard let http = response as? HTTPURLResponse else { throw AIError.bad("Réponse invalide du service de recettes.") }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw AIError.bad(payload["error"] as? String ?? "Impossible d’analyser cette recette (HTTP \(http.statusCode)).")
        }
        let dto = try JSONDecoder().decode(RecipeDTO.self, from: data)
        guard let title = dto.title, !title.isEmpty, let ingredients = dto.ingredients, !ingredients.isEmpty else {
            throw AIError.bad("La recette n’a pas pu être extraite correctement. Essayez une photo plus nette.")
        }
        return dto
    }

    static func editableText(_ recipe: RecipeDTO) -> String {
        var lines = [recipe.title ?? "Ma recette", "", "Ingrédients"]
        lines.append(contentsOf: recipe.ingredients ?? [])
        lines += ["", "Préparation"]
        lines.append(contentsOf: recipe.steps ?? [])
        return lines.joined(separator: "\n")
    }
}

struct RecipeCameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage, onCancel: onCancel) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onImage: (UIImage) -> Void
        let onCancel: () -> Void
        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) { self.onImage = onImage; self.onCancel = onCancel }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImage(image) } else { onCancel() }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onCancel() }
    }
}
