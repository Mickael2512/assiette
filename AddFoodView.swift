import SwiftUI
import PhotosUI
import VisionKit

struct AddFoodView: View {
    let meal: Meal, day: Date
    @Environment(Store.self) var store
    @Environment(\.dismiss) var dismiss
    @State private var mode = 0
    @State private var text = ""
    @State private var busy = false
    @State private var err = ""
    @State private var photoStatus = ""
    @State private var cands: [Cand] = []
    @State private var hits: [OFFResult] = []
    @State private var picked: OFFResult?
    @State private var grams = "100"
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var cam = false
    @State private var searchTask: Task<Void, Never>?

    func add(_ c: Cand) {
        store.add(Entry(date: day, meal: meal, name: c.name, detail: c.detail, m: c.m, source: c.source)); dismiss()
    }
    func run(_ job: @escaping () async throws -> Void) {
        busy = true; err = ""
        Task { do { try await job() } catch { err = error.localizedDescription }; busy = false }
    }
    func searchLocalFood() {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        hits = Ciqual.search(q)
        picked = nil
        if hits.isEmpty {
            photoStatus = Ciqual.rows.isEmpty
                ? "Reconnaissance effectuée sur l’iPhone. Pour retrouver les valeurs nutritionnelles hors ligne, importez d’abord la base CIQUAL dans Réglages."
                : "Aliment reconnu, mais aucune correspondance exacte dans CIQUAL. Essayez un nom plus simple."
        } else {
            photoStatus = "Suggestions nutritionnelles issues de CIQUAL, stocké sur l’iPhone."
        }
    }
    func recognizePhoto(_ image: UIImage) async throws {
        let analysis = try await FoodPhotoAI.analyze(image)
        cands = []
        hits = []
        picked = nil
        text = analysis.dishName

        var suggestions: [Cand] = []
        var unmatched: [String] = []
        for ingredient in analysis.ingredients {
            var matches: [OFFResult] = []
            for term in ([ingredient.name] + ingredient.searchTerms).prefix(5) {
                matches.append(contentsOf: Ciqual.search(term))
                if !matches.isEmpty { break }
            }
            guard let food = matches.first else {
                unmatched.append(ingredient.name)
                continue
            }
            let grams = min(2000, max(1, ingredient.estimatedGrams))
            let confidence = Int((ingredient.confidence * 100).rounded())
            let preparation = ingredient.preparation.isEmpty ? "" : " · " + ingredient.preparation
            suggestions.append(Cand(
                name: food.name,
                detail: "\(Int(grams.rounded())) g estimés · confiance \(confidence)%\(preparation)",
                m: food.per100.scaled(grams / 100),
                source: "CIQUAL · estimation IA"
            ))
        }
        cands = suggestions
        var messages: [String] = []
        if !analysis.uncertainties.isEmpty {
            messages.append(contentsOf: analysis.uncertainties.prefix(3))
        }
        if !unmatched.isEmpty {
            messages.append("À associer manuellement dans CIQUAL : " + unmatched.joined(separator: ", "))
        }
        let confidence = Int((analysis.overallConfidence * 100).rounded())
        photoStatus = "Plat identifié : \(analysis.dishName) · confiance globale \(confidence)%. Les grammes sont estimés, pas pesés."
        if !messages.isEmpty {
            photoStatus += "\n" + messages.joined(separator: "\n")
        }
        if suggestions.isEmpty {
            photoStatus += "\nAucun ingrédient n’a trouvé de correspondance CIQUAL. Importez la base CIQUAL 2025 ou corrigez les noms."
        }
    }
    func go() {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        run {
            if mode == 0 {
                let local = Ciqual.search(q)
                let branded = (try? await FoodDB.search(q)) ?? []
                hits = FoodSearch.merge(ciqual: local, products: branded, query: q)
                cands = []; picked = nil
                if hits.isEmpty {
                    err = Ciqual.rows.isEmpty
                        ? "La base CIQUAL intégrée est indisponible et aucun produit n’a été trouvé en ligne."
                        : "Aucun résultat. Essayez un terme plus court ou scannez le code-barres."
                }
            } else {
                hits = Ciqual.search(q)
                cands = []
                picked = nil
                if hits.isEmpty {
                    err = Ciqual.rows.isEmpty
                        ? "La recherche hors ligne nécessite d’importer la base CIQUAL dans Réglages."
                        : "Aucun aliment correspondant dans CIQUAL. Essayez un nom plus simple."
                }
            }
        }
    }
    func analyze(_ img: UIImage) {
        run { try await recognizePhoto(img) }
    }
    func analyzeItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        run {
            guard let d = try await item.loadTransferable(type: Data.self), let img = UIImage(data: d) else { throw AIError.bad("Photo illisible.") }
            try await recognizePhoto(img)
        }
    }
    func lookup(_ code: String) {
        run {
            if let r = try await FoodDB.barcode(code) { hits = [r]; picked = r; cands = [] }
            else { err = "Produit introuvable dans Open Food Facts." }
        }
    }

    var matchingSavedMeals: [SavedMeal] {
        let query = FoodSearch.normalize(text)
        return store.savedMeals
            .filter { query.isEmpty || FoodSearch.normalize($0.title).contains(query) ||
                FoodSearch.normalize($0.items.map(\.name).joined(separator: " ")).contains(query) }
            .sorted { $0.created > $1.created }
            .prefix(8).map { $0 }
    }

    func add(_ savedMeal: SavedMeal) {
        guard !savedMeal.items.isEmpty else { return }
        for item in savedMeal.items {
            store.add(Entry(date: day, meal: meal, name: item.name,
                            detail: item.detail, m: item.m, source: "Repas enregistré"))
        }
        dismiss()
    }

    var matchingRecipes: [Recipe] {
        let query = FoodSearch.normalize(text)
        let tokens = query.split(separator: " ").map(String.init)
        return store.recipes
            .filter { recipe in
                guard !query.isEmpty else { return true }
                let title = FoodSearch.normalize(recipe.title)
                let ingredients = FoodSearch.normalize(recipe.ingredients.joined(separator: " "))
                return title.contains(query) ||
                    ingredients.contains(query) ||
                    (!tokens.isEmpty && tokens.allSatisfy { token in
                        title.contains(token) || ingredients.contains(token)
                    })
            }
            .sorted {
                if query.isEmpty { return $0.created > $1.created }
                let lhs = FoodSearch.normalize($0.title)
                let rhs = FoodSearch.normalize($1.title)
                let lhsExact = lhs.hasPrefix(query)
                let rhsExact = rhs.hasPrefix(query)
                if lhsExact != rhsExact { return lhsExact }
                return $0.created > $1.created
            }
            .prefix(8).map { $0 }
    }

    func add(_ recipe: Recipe) {
        guard recipe.m.kcal > 0 else {
            err = "Cette recette n’a pas encore de valeurs nutritionnelles. Complétez-la avant de l’ajouter."
            return
        }
        store.add(Entry(date: day, meal: meal, name: recipe.title,
                        detail: "1 portion · recette personnelle", m: recipe.m,
                        source: "Ma bibliothèque"))
        var updated = recipe
        updated.cooked += 1
        updated.lastCooked = Date()
        store.put(updated)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) { Text("Recherche").tag(0); Text("Photo").tag(1); Text("Texte").tag(2) }
                    .pickerStyle(.segmented).listRowBackground(Color.clear)
                if mode == 1 {
                    Section {
                        Button { cam = true } label: { Label("Prendre une photo du plat", systemImage: "camera.fill") }
                        PhotosPicker(selection: $photo, matching: .images) { Label("Choisir dans la photothèque", systemImage: "photo") }
                        TextField("Corriger ou préciser l’aliment", text: $text)
                            .onSubmit(searchLocalFood)
                        Button("Rechercher dans la base hors ligne", action: searchLocalFood)
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                        if !photoStatus.isEmpty {
                            Text(photoStatus).font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Analyse intelligente du plat")
                    } footer: {
                        Text("La photo est analysée par une IA multimodale sécurisée. Les ingrédients sont rapprochés de CIQUAL ; les macros proviennent de la base nutritionnelle. Les poids restent des estimations à vérifier avant validation.")
                    }
                } else {
                    TextField(mode == 0 ? "Ex. œuf, pain de mie, yaourt grec…" : "Nom exact ou approchant d’un aliment", text: $text).onSubmit(go)
                    Button(mode == 0 ? "Rechercher dans les bases" : "Rechercher hors ligne", action: go).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    if mode == 0 {
                        Button { scanning = true } label: { Label("Scanner un code-barres", systemImage: "barcode.viewfinder") }
                            .disabled(!DataScannerViewController.isSupported || !DataScannerViewController.isAvailable)
                    }
                }
                if busy { HStack { ProgressView(); Text("Analyse…").foregroundStyle(.secondary) } }
                if !err.isEmpty { Text(err).foregroundStyle(.red) }
                if !matchingSavedMeals.isEmpty {
                    Section(text.isEmpty ? "Mes repas enregistrés" : "Mes repas") {
                        ForEach(matchingSavedMeals) { savedMeal in
                            Button { add(savedMeal) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "tray.full.fill")
                                        .foregroundStyle(.orange)
                                        .frame(width: 34, height: 34)
                                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(savedMeal.title).foregroundStyle(.primary)
                                        Text("\(savedMeal.items.count) aliments · \(Int(savedMeal.total.kcal.rounded())) kcal")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                                }
                            }
                        }
                    }
                }
                if !matchingRecipes.isEmpty {
                    Section(text.isEmpty ? "Mes recettes et repas enregistrés" : "Dans ma bibliothèque") {
                        ForEach(matchingRecipes) { recipe in
                            Button { add(recipe) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "book.closed.fill")
                                        .foregroundStyle(.green)
                                        .frame(width: 34, height: 34)
                                        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(recipe.title).foregroundStyle(.primary)
                                        Text(recipe.m.kcal > 0
                                             ? "Recette personnelle · 1 portion · \(Int(recipe.m.kcal.rounded())) kcal"
                                             : "Valeurs nutritionnelles à compléter")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                                }
                            }
                            .disabled(recipe.m.kcal <= 0)
                        }
                    }
                }
                if let p = picked {
                    Section("Quantité") {
                        TextField("Grammes", text: $grams).keyboardType(.decimalPad)
                        Button("Ajouter \(p.name)") {
                            guard let quantity = Double(grams.replacingOccurrences(of: ",", with: ".")),
                                  quantity > 0, quantity <= 5000 else {
                                err = "Saisissez une quantité comprise entre 1 et 5 000 g."
                                return
                            }
                            add(Cand(name: p.name, detail: "\(Int(quantity.rounded())) g", m: p.per100.scaled(quantity / 100), source: p.source))
                        }
                    }
                }
                ForEach(hits) { h in
                    Button { picked = h } label: {
                        VStack(alignment: .leading) {
                            Text(h.name).foregroundStyle(.primary)
                            Text("\(h.source) · \(h.brand) · 100 g : \(h.per100.line)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(cands) { c in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.name).font(.body.weight(.medium))
                            Text("\(c.detail) · \(c.m.line)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Ajouter") { add(c) }.buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(meal.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .onChange(of: photo) { _, item in analyzeItem(item) }
            .onChange(of: text) { _, v in
                guard mode == 0 else { return }
                searchTask?.cancel()
                let q = v.trimmingCharacters(in: .whitespacesAndNewlines)
                guard q.count >= 2 else { hits = []; return }
                searchTask = Task {
                    // Affiche d'abord les résultats locaux, puis enrichit avec les produits de marque.
                    let local = Ciqual.search(q)
                    guard !Task.isCancelled else { return }
                    hits = FoodSearch.merge(ciqual: local, products: [], query: q)
                    do {
                        try await Task.sleep(nanoseconds: 280_000_000)
                        guard !Task.isCancelled else { return }
                        let branded = try await FoodDB.search(q)
                        guard !Task.isCancelled else { return }
                        hits = FoodSearch.merge(ciqual: local, products: branded, query: q)
                    } catch {
                        guard !Task.isCancelled else { return }
                        if local.isEmpty { err = "Produits de marque indisponibles. Vérifiez votre connexion Internet." }
                    }
                    cands = []
                    picked = nil
                }
            }
            .onChange(of: mode) { _, _ in photoStatus = ""; err = ""; hits = []; picked = nil }
            .fullScreenCover(isPresented: $cam) { CameraView { analyze($0) }.ignoresSafeArea() }
            .fullScreenCover(isPresented: $scanning) { ScannerSheet { code in scanning = false; lookup(code) } }
        }
    }
}
