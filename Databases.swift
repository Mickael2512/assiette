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
            let handler = VNImageRequestHandler(data: data, options: [:])
            var predictions: [(String, Float)] = []

            // iOS 17 Vision : isole les objets de premier plan, puis classe chaque masque.
            // Cette segmentation est générique, pas une segmentation sémantique d'ingrédients.
            let instanceRequest = VNGenerateForegroundInstanceMaskRequest()
            if (try? handler.perform([instanceRequest])) != nil,
               let observation = instanceRequest.results?.first {
                for instance in Array(observation.allInstances).prefix(6) {
                    guard let masked = try? observation.generateMaskedImage(
                        ofInstances: IndexSet(integer: instance),
                        from: handler,
                        croppedToInstancesExtent: true
                    ) else { continue }
                    let classifier = VNClassifyImageRequest()
                    if (try? VNImageRequestHandler(cvPixelBuffer: masked, options: [:]).perform([classifier])) != nil {
                        predictions.append(contentsOf: (classifier.results ?? []).prefix(5).map {
                            ($0.identifier, $0.confidence)
                        })
                    }
                }
            }

            // Classification de l'image entière en complément et en solution de repli.
            let wholeImage = VNClassifyImageRequest()
            try handler.perform([wholeImage])
            predictions.append(contentsOf: (wholeImage.results ?? []).prefix(15).map {
                ($0.identifier, $0.confidence)
            })
            return predictions
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
    static func barcode(_ code: String) async throws -> OFFResult? {
        var request = URLRequest(url: URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,nutriments")!)
        request.setValue("Assiette/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = json["product"] as? [String: Any],
              let nutrients = product["nutriments"] as? [String: Any] else { return nil }
        func value(_ key: String) -> Double? {
            (nutrients[key] as? NSNumber)?.doubleValue ?? Double(nutrients[key] as? String ?? "")
        }
        guard let kcal = value("energy-kcal_100g"),
              let protein = value("proteins_100g"),
              let fat = value("fat_100g"),
              let carbs = value("carbohydrates_100g") else { return nil }
        return OFFResult(
            name: product["product_name"] as? String ?? "Produit",
            brand: product["brands"] as? String ?? "",
            per100: Macros(kcal: kcal, p: protein, l: fat, g: carbs)
        )
    }
}

enum Ciqual {
    static let file = URL.documentsDirectory.appending(path: "ciqual.csv")
    static var rows: [OFFResult] = []

    private static func parseCSV(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text)
        var index = 0
        while index < chars.count {
            let ch = chars[index]
            if ch == "\"" {
                if quoted && index + 1 < chars.count && chars[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if ch == separator && !quoted {
                row.append(field)
                field = ""
            } else if (ch == "\n" || ch == "\r") && !quoted {
                if ch == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" { index += 1 }
                row.append(field)
                if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
                row = []
                field = ""
            } else {
                field.append(ch)
            }
            index += 1
        }
        row.append(field)
        if row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) { rows.append(row) }
        return rows
    }

    private static func number(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !value.isEmpty, value != "-", !value.lowercased().contains("trace"),
              !value.hasPrefix("<"), let number = Double(value), number.isFinite else { return nil }
        return number
    }

    static func load() {
        rows = []
        // La version officielle CIQUAL est embarquée dans le bundle de l’app.
        // Le fichier importé par l’utilisateur reste prioritaire pour permettre une mise à jour manuelle.
        let bundledURL = Bundle.main.url(forResource: "ciqual", withExtension: "csv")
        let sourceURL = FileManager.default.fileExists(atPath: file.path) ? file : bundledURL
        guard let sourceURL, let data = try? Data(contentsOf: sourceURL),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return }
        let firstLine = text.components(separatedBy: .newlines).first ?? ""
        let separator: Character = firstLine.contains(";") ? ";" : (firstLine.contains("\t") ? "\t" : ",")
        let table = parseCSV(text, separator: separator)
        guard let header = table.first else { return }
        let columns = header.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        func index(_ predicate: (String) -> Bool) -> Int? { columns.firstIndex(where: predicate) }
        guard let nameIndex = index({ $0.contains("alim_nom_fr") || $0.contains("nom français") || $0 == "nom" }),
              let kcalIndex = index({ $0.contains("kcal") }),
              let proteinIndex = index({ $0.hasPrefix("prot") || $0.contains("protéines") }),
              let fatIndex = index({ $0.hasPrefix("lipides") }),
              let carbIndex = index({ $0.hasPrefix("glucides") }) else { return }
        let fiberIndex = index({ $0.contains("fibres alimentaires") || $0.contains("dietary fibre") })
        let sugarIndex = index({ $0.contains("sucres") && !$0.contains("saccharose") })
        let saturatedIndex = index({ $0.contains("acides gras saturés") || $0.contains("saturated fatty acids") })
        let sodiumIndex = index({ $0.contains("sodium") && $0.contains("mg") })

        rows = table.dropFirst().compactMap { fields -> OFFResult? in
            guard fields.indices.contains(max(nameIndex, kcalIndex, proteinIndex, fatIndex, carbIndex)),
                  let kcal = number(fields[kcalIndex]),
                  let protein = number(fields[proteinIndex]),
                  let fat = number(fields[fatIndex]),
                  let carbs = number(fields[carbIndex]) else { return nil }
            func optional(_ column: Int?) -> Double? {
                guard let column, fields.indices.contains(column) else { return nil }
                return number(fields[column])
            }
            let name = fields[nameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return OFFResult(
                name: name,
                brand: "",
                per100: Macros(
                    kcal: kcal, p: protein, l: fat, g: carbs,
                    fiber: optional(fiberIndex), sugars: optional(sugarIndex),
                    saturatedFat: optional(saturatedIndex), sodium: optional(sodiumIndex)
                ),
                source: "CIQUAL"
            )
        }
    }

    private static let concepts: [[String]] = [
        ["oeuf", "omelette", "jaune d oeuf", "blanc d oeuf", "oeuf dur", "oeuf au plat", "oeuf poche", "oeuf brouille", "oeuf a la coque", "oeuf mollet"],
        ["pain de mie", "pain mie", "toast", "pain grille"],
        ["poulet", "volaille", "blanc de poulet", "filet de poulet", "cuisse de poulet", "poulet roti"],
        ["pomme de terre", "pommes de terre", "patate", "pommes vapeur", "frites", "puree"],
        ["pates", "pate", "pasta", "spaghetti", "macaroni", "penne", "coquillettes", "tagliatelles"],
        ["riz", "riz blanc", "riz complet", "riz basmati", "riz thai"],
        ["boeuf", "bœuf", "steak", "steak hache", "viande hachee"],
        ["porc", "cochon", "jambon", "longe de porc", "cote de porc"],
        ["saumon", "truite", "poisson gras"],
        ["thon", "thon en boite"],
        ["yaourt", "yogourt", "yoghourt", "fromage blanc"],
        ["lait", "lait demi ecreme", "lait entier", "lait ecreme"],
        ["fromage", "emmental", "comte", "cheddar", "mozzarella", "parmesan"],
        ["pomme", "pommes", "compote de pomme"],
        ["banane", "bananes"],
        ["tomate", "tomates", "tomate cerise"],
        ["carotte", "carottes"],
        ["courgette", "courgettes"],
        ["brocoli", "brocolis"],
        ["lentille", "lentilles"],
        ["pois chiche", "pois chiches", "chiche"],
        ["haricot", "haricots", "haricot vert", "haricots verts"],
        ["pain", "baguette", "pain complet", "pain blanc", "pain aux cereales"],
        ["crevette", "crevettes", "gambas"],
        ["avocat", "avocats"],
        ["amande", "amandes"],
        ["noix", "noix de cajou", "noisette", "noisettes"]
    ]

    private static func singularize(_ value: String) -> String {
        var result = value
        let replacements = [
            ("oeufs", "oeuf"), ("pommes", "pomme"), ("pates", "pate"),
            ("spaghettis", "spaghetti"), ("lentilles", "lentille"),
            ("carottes", "carotte"), ("tomates", "tomate"), ("courgettes", "courgette"),
            ("brocolis", "brocoli"), ("bananes", "banane"), ("crevettes", "crevette"),
            ("amandes", "amande"), ("noisettes", "noisette"), ("haricots", "haricot"),
            ("pois chiches", "pois chiche")
        ]
        for (plural, singular) in replacements {
            result = result.replacingOccurrences(of: plural, with: singular)
        }
        return result
    }

    private static func isOneEditAway(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 1, min(a.count, b.count) >= 5 else { return false }
        var i = 0, j = 0, edits = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { i += 1; j += 1; continue }
            edits += 1
            if edits > 1 { return false }
            if a.count > b.count { i += 1 }
            else if b.count > a.count { j += 1 }
            else { i += 1; j += 1 }
        }
        if i < a.count || j < b.count { edits += 1 }
        return edits <= 1
    }

    static func search(_ query: String) -> [OFFResult] {
        let term = singularize(FoodSearch.normalize(query))
        guard term.count >= 2 else { return [] }
        let tokens = term.split(separator: " ").map(String.init).filter { $0.count > 1 }
        guard !tokens.isEmpty else { return [] }

        let concept = concepts.first { aliases in
            aliases.contains(where: { alias in
                let normalized = singularize(FoodSearch.normalize(alias))
                return term == normalized || term.contains(normalized) ||
                    (normalized.split(separator: " ").count == 1 && tokens.contains(normalized))
            })
        }

        var ranked: [(item: OFFResult, score: Int)] = []
        var seen = Set<String>()
        for item in rows {
            let name = singularize(FoodSearch.normalize(item.name))
            guard !name.isEmpty else { continue }
            let nameTokens = name.split(separator: " ").map(String.init)
            let allTokens = tokens.allSatisfy { token in
                nameTokens.contains(where: { $0.contains(token) || (token.count >= 5 && isOneEditAway(token, $0)) })
            }
            let conceptMatch = concept?.contains(where: { alias in
                name.contains(singularize(FoodSearch.normalize(alias)))
            }) ?? false
            guard allTokens || conceptMatch else { continue }

            var score = FoodSearch.score(name: item.name, query: term)
            if name == term { score += 1600 }
            else if name.hasPrefix(term) { score += 900 }
            else if name.contains(term) { score += 650 }
            if allTokens { score += 250 }
            if conceptMatch { score += 180 }
            // Les résultats dont le nom correspond précisément à la préparation demandée passent devant les variantes génériques.
            if term.contains("au plat") && name.contains("au plat") { score += 500 }
            if term.contains("dur") && name.contains("dur") { score += 500 }
            if term.contains("complet") && name.contains("complet") { score += 350 }
            if term.contains("demi ecreme") && name.contains("demi ecreme") { score += 350 }
            let key = FoodSearch.normalize(item.name)
            if seen.insert(key).inserted { ranked.append((item, score)) }
        }

        return ranked.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
        }.prefix(60).map(\.item)
    }

    static func importFile(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let temporary = file.appendingPathExtension("importing")
        let backup = file.appendingPathExtension("previous")
        try? FileManager.default.removeItem(at: temporary)
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.copyItem(at: url, to: temporary)
        let previousRows = rows
        let hadPrevious = FileManager.default.fileExists(atPath: file.path)
        if hadPrevious { try FileManager.default.copyItem(at: file, to: backup) }
        do {
            let data = try Data(contentsOf: temporary)
            try data.write(to: file, options: .atomic)
            load()
            guard !rows.isEmpty else { throw AIError.bad("Le fichier ne contient aucune ligne CIQUAL exploitable. Vérifiez l’export CSV et ses colonnes.") }
            try? FileManager.default.removeItem(at: temporary)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            try? FileManager.default.removeItem(at: file)
            if hadPrevious { try? FileManager.default.moveItem(at: backup, to: file) }
            rows = previousRows
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

struct BarcodeScanner: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
            recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }
    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onCode) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var completed = false
        init(_ callback: @escaping (String) -> Void) { onCode = callback }
        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !completed else { return }
            for case .barcode(let barcode) in items {
                if let code = barcode.payloadStringValue {
                    completed = true
                    onCode(code)
                    break
                }
            }
        }
    }
}

struct ScannerSheet: View {
    var onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            BarcodeScanner(onCode: onCode).ignoresSafeArea()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
        }
    }
}

struct CameraView: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
