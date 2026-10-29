import SwiftUI

enum AIError: LocalizedError {
    case noKey, bad(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "Ajoutez votre clé Gemini gratuite dans Réglages."
        case .bad(let s): return s
        }
    }
}

struct FoodDTO: Decodable { var name: String; var portion: String?; var kcal: Double?; var p: Double?; var l: Double?; var g: Double? }
struct FoodsDTO: Decodable { var items: [FoodDTO] }
struct RecipeDTO: Decodable {
    var title: String?; var servings: Int?; var ingredients: [String]?; var steps: [String]?
    var kcal: Double?; var p: Double?; var l: Double?; var g: Double?; var error: String?
}

enum AI {
    static func json<T: Decodable>(_ t: T.Type, prompt: String, image: UIImage? = nil) async throws -> T {
        let ud = UserDefaults.standard
        guard let key = ud.string(forKey: "geminiKey")?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { throw AIError.noKey }
        let model = ud.string(forKey: "geminiModel").flatMap { $0.isEmpty ? nil : $0 } ?? "gemini-2.5-flash"
        var parts: [[String: Any]] = [["text": prompt]]
        if let d = image?.resized(1280).jpegData(compressionQuality: 0.8) {
            parts.append(["inline_data": ["mime_type": "image/jpeg", "data": d.base64EncodedString()]])
        }
        let body: [String: Any] = ["contents": [["parts": parts]], "generationConfig": ["response_mime_type": "application/json"]]
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        req.httpMethod = "POST"; req.timeoutInterval = 90
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key"); req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (d, _) = try await URLSession.shared.data(for: req)
        guard let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { throw AIError.bad("Réponse invalide.") }
        if let e = o["error"] as? [String: Any] { throw AIError.bad(e["message"] as? String ?? "Erreur de l’API.") }
        let c = (o["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any]
        let text = ((c?["parts"] as? [[String: Any]])?.compactMap { $0["text"] as? String } ?? []).joined()
        guard let a = text.firstIndex(of: "{"), let b = text.lastIndex(of: "}") else { throw AIError.bad("Réponse illisible, réessayez.") }
        do { return try JSONDecoder().decode(T.self, from: Data(text[a...b].utf8)) }
        catch { throw AIError.bad("Réponse inattendue de l’IA, réessayez.") }
    }

    static func estimate(_ text: String, _ img: UIImage?) async throws -> [Cand] {
        let ctx = img == nil ? "La personne a mangé : « \(text) »." : "Identifie les aliments de la photo. \(text)"
        let f = try await json(FoodsDTO.self, prompt: ctx + " Estime une portion réaliste pour chaque élément (1 à 6). JSON uniquement : {\"items\":[{\"name\":\"\",\"portion\":\"150 g\",\"kcal\":0,\"p\":0,\"l\":0,\"g\":0}]} (p protéines, l lipides, g glucides, en grammes). En français.", image: img)
        return f.items.map { Cand(name: $0.name, detail: $0.portion ?? "", m: Macros(kcal: $0.kcal ?? 0, p: $0.p ?? 0, l: $0.l ?? 0, g: $0.g ?? 0), source: "Estimation IA") }
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
            guard let kcal = v("energy-kcal_100g") else { return nil }
            return OFFResult(name: n, brand: p["brands"] as? String ?? "", per100: Macros(kcal: kcal, p: v("proteins_100g") ?? 0, l: v("fat_100g") ?? 0, g: v("carbohydrates_100g") ?? 0))
        }
    }
}

enum Importer {
    static let fmt = "Réponds uniquement en JSON : {\"title\":\"\",\"servings\":2,\"ingredients\":[\"200 g de riz\"],\"steps\":[\"…\"],\"kcal\":0,\"p\":0,\"l\":0,\"g\":0} avec kcal, p (protéines), l (lipides), g (glucides) PAR PORTION, estimés d’après les ingrédients (jamais 0, nombres seuls). Si aucune recette n’est identifiable : {\"error\":\"raison\"}. En français."

    static func prompt(_ src: String) -> String { "Extrais la recette de ce contenu (ingrédients et étapes tels qu’écrits, sans rien inventer). " + fmt + "\n\n" + src }

    static func rx(_ p: String, _ s: String) -> [String] {
        guard let r = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        return r.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in Range(m.range(at: 1), in: s).map { String(s[$0]) } }
    }
    static func meta(_ k: String, _ h: String) -> String {
        let a = rx("<meta[^>]+(?:property|name)=\"\(k)\"[^>]*content=\"([^\"]*)\"", h)
        let b = rx("<meta[^>]+content=\"([^\"]*)\"[^>]*(?:property|name)=\"\(k)\"", h)
        return (a.first ?? b.first ?? "").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&#039;", with: "'").replacingOccurrences(of: "&#x27;", with: "'")
    }

    static func fromURL(_ s: String) async throws -> (RecipeDTO, Data?) {
        guard let url = URL(string: s) else { throw AIError.bad("Lien invalide.") }
        var r = URLRequest(url: url)
        r.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        r.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        let d = (try? await URLSession.shared.data(for: r))?.0 ?? Data()
        let html = String(decoding: d, as: UTF8.self)
        var text = "Titre : \(meta("og:title", html))\nDescription : \(meta("og:description", html))\n"
        for b in rx("<script[^>]*application/ld\\+json[^>]*>(.*?)</script>", html).prefix(3) { text += "\nJSON-LD : " + b.prefix(6000) }
        var img = meta("og:image", html)
        if url.host?.contains("tiktok.com") == true,
           let o = URL(string: "https://www.tiktok.com/oembed?url=" + (s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s)),
           let od = (try? await URLSession.shared.data(from: o))?.0,
           let j = try? JSONSerialization.jsonObject(with: od) as? [String: Any] {
            text = "Légende de la publication : \(j["title"] as? String ?? "")\n" + text
            if let t = j["thumbnail_url"] as? String { img = t }
        }
        let dto = try await AI.json(RecipeDTO.self, prompt: prompt(text))
        var data: Data?
        if let u = URL(string: img), !img.isEmpty, let raw = try? await URLSession.shared.data(from: u).0 {
            data = UIImage(data: raw)?.resized(900).jpegData(compressionQuality: 0.8)
        }
        return (dto, data)
    }
}
