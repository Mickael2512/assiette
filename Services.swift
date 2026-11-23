import SwiftUI

enum AIError: LocalizedError {
    case bad(String)
    var errorDescription: String? {
        switch self {
        case .bad(let message): return message
        }
    }
}

struct RecipeDTO: Decodable {
    var title: String?
    var servings: Int?
    var ingredients: [String]?
    var steps: [String]?
    var kcal: Double?
    var p: Double?
    var l: Double?
    var g: Double?
    var error: String?

    init(title: String? = nil, servings: Int? = nil, ingredients: [String]? = nil, steps: [String]? = nil,
         kcal: Double? = nil, p: Double? = nil, l: Double? = nil, g: Double? = nil, error: String? = nil) {
        self.title = title
        self.servings = servings
        self.ingredients = ingredients
        self.steps = steps
        self.kcal = kcal
        self.p = p
        self.l = l
        self.g = g
        self.error = error
    }
}


struct OFFResult: Identifiable { let id = UUID(); var name: String; var brand: String; var per100: Macros; var source = "Open Food Facts" }

enum FoodDB {
    static func search(_ q: String) async throws -> [OFFResult] {
        var c = URLComponents(string: "https://fr.openfoodfacts.org/cgi/search.pl")!
        c.queryItems = [("search_terms", q), ("search_simple", "1"), ("action", "process"), ("json", "1"), ("page_size", "20"), ("fields", "product_name,brands,nutriments")].map { URLQueryItem(name: $0.0, value: $0.1) }
        var r = URLRequest(url: c.url!); r.setValue("Assiette/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (d, _) = try await URLSession.shared.data(for: r)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], let ps = j["products"] as? [[String: Any]] else { return [] }
        return ps.compactMap { p -> OFFResult? in
            guard let n = p["product_name"] as? String, !n.isEmpty, let nu = p["nutriments"] as? [String: Any] else { return nil }
            func v(_ k: String) -> Double? { (nu[k] as? NSNumber)?.doubleValue ?? Double(nu[k] as? String ?? "") }
            guard let kcal = v("energy-kcal_100g"), let protein = v("proteins_100g"),
                  let fat = v("fat_100g"), let carbs = v("carbohydrates_100g") else { return nil }
            return OFFResult(name: n, brand: p["brands"] as? String ?? "", per100: Macros(kcal: kcal, p: protein, l: fat, g: carbs))
        }
    }
}

enum Importer {
    static func rx(_ pattern: String, _ source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    static func meta(_ key: String, _ html: String) -> String {
        let a = rx(#"<meta[^>]+(?:property|name)="\#(key)"[^>]*content="([^"]*)""#, html)
        let b = rx(#"<meta[^>]+content="([^"]*)"[^>]*(?:property|name)="\#(key)""#, html)
        return (a.first ?? b.first ?? "")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func typeIsRecipe(_ value: Any?) -> Bool {
        func matches(_ type: String) -> Bool {
            let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "recipe" || normalized.hasSuffix("/recipe") || normalized.hasSuffix("#recipe")
        }
        if let type = value as? String { return matches(type) }
        if let types = value as? [String] { return types.contains(where: matches) }
        return false
    }

    private static func recipeObject(_ value: Any) -> [String: Any]? {
        if let dict = value as? [String: Any] {
            if typeIsRecipe(dict["@type"]) { return dict }
            for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement"] {
                if let nested = dict[key], let found = recipeObject(nested) { return found }
            }
            for nested in dict.values {
                if let found = recipeObject(nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = recipeObject(nested) { return found }
            }
        }
        return nil
    }

    private static func strings(_ value: Any?) -> [String] {
        guard let value else { return [] }
        if let string = value as? String { return [string] }
        if let array = value as? [Any] { return array.flatMap { strings($0) } }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String { return [text] }
            if let elements = dict["itemListElement"] { return strings(elements) }
        }
        return []
    }

    private static func amount(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return number.doubleValue }
        guard let string = value as? String else { return nil }
        let match = rx("([0-9]+(?:[.,][0-9]+)?)", string).first
        return match.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
    }

    static func fromText(_ source: String) throws -> RecipeDTO {
        let lines = source.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let title = lines.first, lines.count > 1 else {
            throw AIError.bad("Ajoutez un titre, puis les sections Ingrédients et Préparation.")
        }
        var section = ""
        var ingredients: [String] = []
        var steps: [String] = []
        for line in lines.dropFirst() {
            let normalized = line.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " :"))
            if ["ingrédients", "ingredients"].contains(normalized) { section = "ingredients"; continue }
            if ["préparation", "preparation", "étapes", "etapes", "instructions"].contains(normalized) { section = "steps"; continue }
            let cleaned = line.replacingOccurrences(of: #"^[-•*0-9.) ]+"#, with: "", options: .regularExpression)
            if section == "ingredients" { ingredients.append(cleaned) }
            if section == "steps" { steps.append(cleaned) }
        }
        guard !ingredients.isEmpty else {
            throw AIError.bad("Aucun ingrédient reconnu. Structurez le texte avec les titres « Ingrédients » et « Préparation ».")
        }
        return RecipeDTO(title: title, servings: 1, ingredients: ingredients, steps: steps)
    }

    static func fromURL(_ source: String) async throws -> (RecipeDTO, Data?) {
        guard let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw AIError.bad("Lien invalide. Utilisez une adresse HTTP ou HTTPS.")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Assiette/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            throw AIError.bad("Le site n’a pas permis de récupérer la recette.")
        }
        let html = String(decoding: data, as: UTF8.self)
        var recipe: [String: Any]?
        for block in rx(#"<script[^>]*type=["']application/ld\+json["'][^>]*>(.*?)</script>"#, html) {
            guard let json = block.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: json, options: [.fragmentsAllowed]),
                  let found = recipeObject(object) else { continue }
            recipe = found
            break
        }
        guard let recipe else {
            throw AIError.bad("Aucune recette structurée détectée sur cette page. Collez le texte de la recette avec les sections Ingrédients et Préparation.")
        }
        let nutrition = recipe["nutrition"] as? [String: Any] ?? [:]
        let servings = amount(recipe["recipeYield"]).map { max(1, Int($0)) } ?? 1
        let instructions = strings(recipe["recipeInstructions"])
        let ingredients = strings(recipe["recipeIngredient"])
        guard !ingredients.isEmpty else { throw AIError.bad("La page contient une recette mais aucune liste d’ingrédients exploitable.") }
        let imageString: String? = {
            if let image = recipe["image"] as? String { return image }
            if let image = recipe["image"] as? [String] { return image.first }
            if let image = recipe["image"] as? [String: Any] { return image["url"] as? String }
            return nil
        }()
        let dto = RecipeDTO(
            title: recipe["name"] as? String ?? meta("og:title", html),
            servings: servings,
            ingredients: ingredients,
            steps: instructions,
            kcal: amount(nutrition["calories"]),
            p: amount(nutrition["proteinContent"]),
            l: amount(nutrition["fatContent"]),
            g: amount(nutrition["carbohydrateContent"])
        )
        var imageData: Data?
        if let imageString, let imageURL = URL(string: imageString, relativeTo: url)?.absoluteURL,
           ["http", "https"].contains(imageURL.scheme?.lowercased() ?? ""),
           let raw = try? await URLSession.shared.data(from: imageURL).0 {
            imageData = UIImage(data: raw)?.resized(900).jpegData(compressionQuality: 0.8)
        }
        return (dto, imageData)
    }
}
