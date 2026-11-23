import SwiftUI
import Vision
import VisionKit

struct FoodRecognition: Identifiable {
    let id = UUID()
    let name: String
    let searchTerm: String
    let confidence: Float
}

/// Reconnaissance locale via Vision : l'image reste sur l'appareil.
enum OnDeviceFoodRecognition {
    private static let foodLabels: [String: (name: String, search: String)] = [
        "pizza": ("Pizza", "pizza"),
        "cheeseburger": ("Cheeseburger", "hamburger"),
        "hamburger": ("Hamburger", "hamburger"),
        "hotdog": ("Hot-dog", "hot-dog"),
        "hot dog": ("Hot-dog", "hot-dog"),
        "french fries": ("Frites", "frites"),
        "mashed potato": ("Purée de pommes de terre", "purée"),
        "baked potato": ("Pomme de terre au four", "pomme de terre"),
        "spaghetti": ("Spaghetti", "pâtes"),
        "carbonara": ("Pâtes à la carbonara", "pâtes"),
        "pasta": ("Pâtes", "pâtes"),
        "noodle": ("Nouilles", "nouilles"),
        "ramen": ("Ramen", "ramen"),
        "sushi": ("Sushi", "sushi"),
        "sashimi": ("Sashimi", "sashimi"),
        "burrito": ("Burrito", "burrito"),
        "taco": ("Tacos", "tacos"),
        "guacamole": ("Guacamole", "guacamole"),
        "salad": ("Salade composée", "salade"),
        "soup": ("Soupe", "soupe"),
        "sandwich": ("Sandwich", "sandwich"),
        "bread": ("Pain", "pain"),
        "french loaf": ("Baguette", "baguette"),
        "bagel": ("Bagel", "bagel"),
        "croissant": ("Croissant", "croissant"),
        "pretzel": ("Bretzel", "bretzel"),
        "waffle": ("Gaufre", "gaufre"),
        "pancake": ("Pancakes", "pancake"),
        "omelet": ("Omelette", "omelette"),
        "fried egg": ("Œuf au plat", "œuf"),
        "boiled egg": ("Œuf dur", "œuf"),
        "apple": ("Pomme", "pomme"),
        "granny smith": ("Pomme", "pomme"),
        "banana": ("Banane", "banane"),
        "strawberry": ("Fraise", "fraise"),
        "orange": ("Orange", "orange"),
        "lemon": ("Citron", "citron"),
        "pineapple": ("Ananas", "ananas"),
        "watermelon": ("Pastèque", "pastèque"),
        "broccoli": ("Brocoli", "brocoli"),
        "cauliflower": ("Chou-fleur", "chou-fleur"),
        "cucumber": ("Concombre", "concombre"),
        "zucchini": ("Courgette", "courgette"),
        "mushroom": ("Champignon", "champignon"),
        "corn": ("Maïs", "maïs"),
        "bell pepper": ("Poivron", "poivron"),
        "carrot": ("Carotte", "carotte"),
        "tomato": ("Tomate", "tomate"),
        "steak": ("Steak", "bœuf"),
        "beef": ("Bœuf", "bœuf"),
        "chicken": ("Poulet", "poulet"),
        "roast chicken": ("Poulet rôti", "poulet"),
        "salmon": ("Saumon", "saumon"),
        "fish": ("Poisson", "poisson"),
        "shrimp": ("Crevettes", "crevette"),
        "prawn": ("Crevettes", "crevette"),
        "cheese": ("Fromage", "fromage"),
        "yogurt": ("Yaourt", "yaourt"),
        "ice cream": ("Glace", "glace"),
        "chocolate cake": ("Gâteau au chocolat", "gâteau au chocolat"),
        "cheesecake": ("Cheesecake", "cheesecake"),
        "pudding": ("Crème dessert", "crème dessert"),
        "rice": ("Riz", "riz")
    ]

    static func recognize(_ image: UIImage) async throws -> [FoodRecognition] {
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            throw AIError.bad("Impossible de lire cette photo.")
        }

        let raw = try await Task.detached(priority: .userInitiated) { () throws -> [(String, Float)] in
            let request = VNClassifyImageRequest()
            request.imageCropAndScaleOption = .centerCrop
            try VNImageRequestHandler(data: data, options: [:]).perform([request])
            return (request.results ?? []).prefix(15).map { ($0.identifier, $0.confidence) }
        }.value

        var seen = Set<String>()
        return raw.compactMap { identifier, confidence in
            let key = identifier.lowercased().replacingOccurrences(of: "_", with: " ")
            guard confidence >= 0.025,
                  let match = foodLabels[key] ?? foodLabels.first(where: { key.contains($0.key) })?.value,
                  seen.insert(match.search).inserted else { return nil }
            return FoodRecognition(name: match.name, searchTerm: match.search, confidence: confidence)
        }.prefix(5).map { $0 }
    }
}

extension FoodDB {
    static func usda(_ q: String) async throws -> [OFFResult] {
        let key = UserDefaults.standard.string(forKey: "usdaKey").flatMap { $0.isEmpty ? nil : $0 } ?? "DEMO_KEY"
        var c = URLComponents(string: "https://api.nal.usda.gov/fdc/v1/foods/search")!
        c.queryItems = [("query", q), ("pageSize", "12"), ("dataType", "Foundation,SR Legacy"), ("api_key", key)].map { URLQueryItem(name: $0.0, value: $0.1) }
        let (d, _) = try await URLSession.shared.data(from: c.url!)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], let fs = j["foods"] as? [[String: Any]] else { return [] }
        return fs.compactMap { f -> OFFResult? in
            guard let n = f["description"] as? String, let ns = f["foodNutrients"] as? [[String: Any]] else { return nil }
            func v(_ num: String) -> Double? { ns.first { ($0["nutrientNumber"] as? String) == num }.flatMap { ($0["value"] as? NSNumber)?.doubleValue } }
            guard let kcal = v("208") else { return nil }
            return OFFResult(name: n, brand: "", per100: Macros(kcal: kcal, p: v("203") ?? 0, l: v("204") ?? 0, g: v("205") ?? 0), source: "USDA")
        }
    }

    static func barcode(_ code: String) async throws -> OFFResult? {
        var r = URLRequest(url: URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments")!)
        r.setValue("Assiette/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (d, _) = try await URLSession.shared.data(for: r)
        guard let j = try JSONSerialization.jsonObject(with: d) as? [String: Any], let p = j["product"] as? [String: Any],
              let nu = p["nutriments"] as? [String: Any] else { return nil }
        func v(_ k: String) -> Double? { (nu[k] as? NSNumber)?.doubleValue ?? Double(nu[k] as? String ?? "") }
        guard let kcal = v("energy-kcal_100g") else { return nil }
        return OFFResult(name: p["product_name"] as? String ?? "Produit", brand: p["brands"] as? String ?? "",
                         per100: Macros(kcal: kcal, p: v("proteins_100g") ?? 0, l: v("fat_100g") ?? 0, g: v("carbohydrates_100g") ?? 0))
    }
}

enum Ciqual {
    static let file = URL.documentsDirectory.appending(path: "ciqual.csv")
    static var rows: [OFFResult] = []

    static func split(_ line: String, _ sep: Character) -> [String] {
        var out: [String] = [], cur = "", q = false
        for ch in line {
            if ch == "\"" { q.toggle() } else if ch == sep && !q { out.append(cur); cur = "" } else { cur.append(ch) }
        }
        out.append(cur); return out
    }
    static func num(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "<", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
    }
    static func load() {
        rows = []
        guard let d = try? Data(contentsOf: file), let t = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) else { return }
        let lines = t.split(whereSeparator: \.isNewline).map(String.init)
        guard let h = lines.first else { return }
        let sep: Character = h.contains(";") ? ";" : (h.contains("\t") ? "\t" : ",")
        let cols = split(h, sep).map { $0.lowercased() }
        func idx(_ f: (String) -> Bool) -> Int? { cols.firstIndex(where: f) }
        guard let n = idx({ $0.contains("alim_nom_fr") }),
              let k = idx({ $0.contains("kcal") && $0.contains("1169") }) ?? idx({ $0.contains("kcal") }),
              let p = idx({ $0.hasPrefix("prot") }), let l = idx({ $0.hasPrefix("lipides") }), let g = idx({ $0.hasPrefix("glucides") }) else { return }
        rows = lines.dropFirst().compactMap { ln -> OFFResult? in
            let c = split(ln, sep)
            guard c.count > max(n, k, p, l, g) else { return nil }
            return OFFResult(name: c[n], brand: "", per100: Macros(kcal: num(c[k]), p: num(c[p]), l: num(c[l]), g: num(c[g])), source: "CIQUAL")
        }
    }
    static func search(_ q: String) -> [OFFResult] {
        Array(rows.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }.prefix(15))
    }
    static func importFile(_ url: URL) throws {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.copyItem(at: url, to: file)
        load()
    }
}

struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let v = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced, recognizesMultipleItems: false,
                                          isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        v.delegate = context.coordinator
        return v
    }
    func updateUIViewController(_ v: DataScannerViewController, context: Context) { if !v.isScanning { try? v.startScanning() } }
    func makeCoordinator() -> Coord { Coord(onCode) }
    final class Coord: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var done = false
        init(_ f: @escaping (String) -> Void) { onCode = f }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let b) in items {
                if let p = b.payloadStringValue { done = true; onCode(p); break }
            }
        }
    }
}

struct ScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            BarcodeScanner(onCode: onCode).ignoresSafeArea()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ v: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coord { Coord(self) }
    final class Coord: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let p: CameraView
        init(_ p: CameraView) { self.p = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let i = info[.originalImage] as? UIImage { p.onImage(i) }
            p.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { p.dismiss() }
    }
}
