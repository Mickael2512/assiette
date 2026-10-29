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
    var kcal = 0.0, p = 0.0, l = 0.0, g = 0.0
    static func + (a: Macros, b: Macros) -> Macros { Macros(kcal: a.kcal + b.kcal, p: a.p + b.p, l: a.l + b.l, g: a.g + b.g) }
    func scaled(_ f: Double) -> Macros { Macros(kcal: kcal * f, p: p * f, l: l * f, g: g * f) }
    var line: String { "\(Int(kcal.rounded())) kcal · P \(Int(p.rounded())) · L \(Int(l.rounded())) · G \(Int(g.rounded()))" }
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
    var entries: [Entry] = []
    var recipes: [Recipe] = []
    var goal = Macros(kcal: 2200, p: 140, l: 70, g: 250)

    private struct Snap: Codable { var entries: [Entry]; var recipes: [Recipe]; var goal: Macros }
    private static let url = URL.documentsDirectory.appending(path: "assiette.json")

    init() {
        Ciqual.load()
        if let d = try? Data(contentsOf: Self.url), let s = try? JSONDecoder().decode(Snap.self, from: d) {
            entries = s.entries; recipes = s.recipes; goal = s.goal
        }
    }
    func save() {
        if let d = try? JSONEncoder().encode(Snap(entries: entries, recipes: recipes, goal: goal)) {
            try? d.write(to: Self.url, options: .atomic)
        }
    }
    func list(_ day: Date, _ meal: Meal) -> [Entry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) && $0.meal == meal }
    }
    func total(_ day: Date, _ meal: Meal? = nil) -> Macros {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) && (meal == nil || $0.meal == meal) }
            .reduce(Macros()) { $0 + $1.m }
    }
    func add(_ e: Entry) { entries.append(e); save() }
    func remove(_ ids: [UUID]) { entries.removeAll { ids.contains($0.id) }; save() }
    func put(_ r: Recipe) {
        if let i = recipes.firstIndex(where: { $0.id == r.id }) { recipes[i] = r } else { recipes.insert(r, at: 0) }
        save()
    }
    func drop(_ id: UUID) { recipes.removeAll { $0.id == id }; save() }
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
