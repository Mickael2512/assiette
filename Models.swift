import SwiftUI

enum Meal: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner
    var id: String { rawValue }
    var title: String {
        switch self {
        case .breakfast: return "Petit-déjeuner"
        case .lunch: return "Déjeuner"
        case .snack: return "Collation"
        case .dinner: return "Dîner"
        }
    }
    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .snack: return "leaf.fill"
        case .dinner: return "moon.stars.fill"
        }
    }
    var color: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .snack: return .green
        case .dinner: return .indigo
        }
    }
}

struct Macros: Codable, Hashable {
    var kcal: Double
    var p: Double
    var l: Double
    var g: Double
    /// Nutriments facultatifs : nil signifie « donnée inconnue », jamais zéro.
    var fiber: Double?
    var sugars: Double?
    var saturatedFat: Double?
    var sodium: Double?

    init(
        kcal: Double = 0,
        p: Double = 0,
        l: Double = 0,
        g: Double = 0,
        fiber: Double? = nil,
        sugars: Double? = nil,
        saturatedFat: Double? = nil,
        sodium: Double? = nil
    ) {
        self.kcal = kcal
        self.p = p
        self.l = l
        self.g = g
        self.fiber = fiber
        self.sugars = sugars
        self.saturatedFat = saturatedFat
        self.sodium = sodium
    }

    private enum CodingKeys: String, CodingKey {
        case kcal, p, l, g, fiber, sugars, saturatedFat, sodium
    }

    /// Les anciennes sauvegardes conservent leurs quatre macros historiques.
    /// Les nutriments secondaires absents restent inconnus (nil), pas zéro.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kcal = try values.decodeIfPresent(Double.self, forKey: .kcal) ?? 0
        p = try values.decodeIfPresent(Double.self, forKey: .p) ?? 0
        l = try values.decodeIfPresent(Double.self, forKey: .l) ?? 0
        g = try values.decodeIfPresent(Double.self, forKey: .g) ?? 0
        fiber = try values.decodeIfPresent(Double.self, forKey: .fiber)
        sugars = try values.decodeIfPresent(Double.self, forKey: .sugars)
        saturatedFat = try values.decodeIfPresent(Double.self, forKey: .saturatedFat)
        sodium = try values.decodeIfPresent(Double.self, forKey: .sodium)
    }

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(
            kcal: a.kcal + b.kcal,
            p: a.p + b.p,
            l: a.l + b.l,
            g: a.g + b.g,
            fiber: (a.fiber != nil && b.fiber != nil) ? a.fiber! + b.fiber! : nil,
            sugars: (a.sugars != nil && b.sugars != nil) ? a.sugars! + b.sugars! : nil,
            saturatedFat: (a.saturatedFat != nil && b.saturatedFat != nil) ? a.saturatedFat! + b.saturatedFat! : nil,
            sodium: (a.sodium != nil && b.sodium != nil) ? a.sodium! + b.sodium! : nil
        )
    }

    func scaled(_ factor: Double) -> Macros {
        Macros(
            kcal: kcal * factor,
            p: p * factor,
            l: l * factor,
            g: g * factor,
            fiber: fiber.map { $0 * factor },
            sugars: sugars.map { $0 * factor },
            saturatedFat: saturatedFat.map { $0 * factor },
            sodium: sodium.map { $0 * factor }
        )
    }

    var line: String {
        "\(Int(kcal.rounded())) kcal · P \(Int(p.rounded())) · L \(Int(l.rounded())) · G \(Int(g.rounded()))"
    }
}

struct Entry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var meal: Meal
    var name: String
    var detail: String
    var m: Macros
    var source: String
}

struct Recipe: Codable, Identifiable {
    var id = UUID()
    var title: String
    var servings: Int
    var ingredients: [String]
    var steps: [String]
    var m: Macros
    var image: Data?
    var url: String?
    var cooked = 0
    var lastCooked: Date?
    var created = Date()
}

struct Cand: Identifiable {
    let id = UUID()
    var name: String
    var detail: String
    var m: Macros
    var source: String
}

@Observable final class Store {
    static let currentSchemaVersion = 2

    var entries: [Entry] = []
    var recipes: [Recipe] = []
    var goal = Macros(kcal: 2200, p: 140, l: 70, g: 250)
    var bodyMeasurements: [BodyMeasurement] = []
    var bodyProfile = BodyProfile()
    var bodyGoals = BodyGoals()

    private struct Snap: Codable {
        var schemaVersion: Int
        var entries: [Entry]
        var recipes: [Recipe]
        var goal: Macros
        var bodyMeasurements: [BodyMeasurement]
        var bodyProfile: BodyProfile
        var bodyGoals: BodyGoals

        private enum CodingKeys: String, CodingKey {
            case schemaVersion, entries, recipes, goal, bodyMeasurements, bodyProfile, bodyGoals
        }

        init(
            schemaVersion: Int = Store.currentSchemaVersion,
            entries: [Entry],
            recipes: [Recipe],
            goal: Macros,
            bodyMeasurements: [BodyMeasurement],
            bodyProfile: BodyProfile,
            bodyGoals: BodyGoals
        ) {
            self.schemaVersion = schemaVersion
            self.entries = entries
            self.recipes = recipes
            self.goal = goal
            self.bodyMeasurements = bodyMeasurements
            self.bodyProfile = bodyProfile
            self.bodyGoals = bodyGoals
        }

        /// Accepte le format historique sans version ni données corporelles.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            entries = try values.decodeIfPresent([Entry].self, forKey: .entries) ?? []
            recipes = try values.decodeIfPresent([Recipe].self, forKey: .recipes) ?? []
            goal = try values.decodeIfPresent(Macros.self, forKey: .goal)
                ?? Macros(kcal: 2200, p: 140, l: 70, g: 250)
            bodyMeasurements = try values.decodeIfPresent([BodyMeasurement].self, forKey: .bodyMeasurements) ?? []
            bodyProfile = try values.decodeIfPresent(BodyProfile.self, forKey: .bodyProfile) ?? BodyProfile()
            bodyGoals = try values.decodeIfPresent(BodyGoals.self, forKey: .bodyGoals) ?? BodyGoals()
        }
    }

    private static let url = URL.documentsDirectory.appending(path: "assiette.json")

    init() {
        Ciqual.load()
        guard let data = try? Data(contentsOf: Self.url),
              let snapshot = try? JSONDecoder().decode(Snap.self, from: data) else { return }

        entries = snapshot.entries
        recipes = snapshot.recipes
        goal = snapshot.goal
        bodyMeasurements = snapshot.bodyMeasurements
        bodyProfile = snapshot.bodyProfile
        bodyGoals = snapshot.bodyGoals

        if snapshot.schemaVersion < Self.currentSchemaVersion {
            save()
        }
    }

    func save() {
        let snapshot = Snap(
            entries: entries,
            recipes: recipes,
            goal: goal,
            bodyMeasurements: bodyMeasurements,
            bodyProfile: bodyProfile,
            bodyGoals: bodyGoals
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: Self.url, options: .atomic)
    }

    func list(_ day: Date, _ meal: Meal) -> [Entry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.meal == meal }
    }

    func total(_ day: Date, _ meal: Meal? = nil) -> Macros {
        let matching = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) && (meal == nil || $0.meal == meal) }
        guard let first = matching.first else { return Macros() }
        return matching.dropFirst().reduce(first.m) { $0 + $1.m }
    }

    func add(_ entry: Entry) {
        entries.append(entry)
        save()
    }

    func remove(_ ids: [UUID]) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func put(_ recipe: Recipe) {
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.insert(recipe, at: 0)
        }
        save()
    }

    func drop(_ id: UUID) {
        recipes.removeAll { $0.id == id }
        save()
    }

    func addBodyMeasurement(_ measurement: BodyMeasurement) {
        guard measurement.hasValues else { return }
        bodyMeasurements.append(measurement)
        bodyMeasurements.sort { $0.date > $1.date }
        save()
    }

    func updateBodyMeasurement(_ measurement: BodyMeasurement) {
        guard let index = bodyMeasurements.firstIndex(where: { $0.id == measurement.id }) else { return }
        bodyMeasurements[index] = measurement
        bodyMeasurements.sort { $0.date > $1.date }
        save()
    }

    func removeBodyMeasurements(_ ids: [UUID]) {
        bodyMeasurements.removeAll { ids.contains($0.id) }
        save()
    }
}

func frDate(_ d: Date, _ f: String) -> String {
    let x = DateFormatter(); x.locale = Locale(identifier: "fr_FR"); x.dateFormat = f
    let s = x.string(from: d)
    return s.prefix(1).uppercased() + s.dropFirst()
}

extension UIImage {
    func resized(_ m: CGFloat) -> UIImage {
        let k = min(1, m / max(size.width, size.height))
        let s = CGSize(width: size.width * k, height: size.height * k)
        let f = UIGraphicsImageRendererFormat(); f.scale = 1
        return UIGraphicsImageRenderer(size: s, format: f).image { _ in draw(in: CGRect(origin: .zero, size: s)) }
    }
}

extension View {
    func card(_ r: CGFloat = 22) -> some View {
        background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: r, style: .continuous))
    }
}
