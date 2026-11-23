import SwiftUI
import PhotosUI

struct RecipeImage: View {
    let data: Data?
    var body: some View {
        if let d = data, let i = UIImage(data: d) {
            Image(uiImage: i).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [.green.opacity(0.35), .mint.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { Image(systemName: "fork.knife").font(.largeTitle).foregroundStyle(.white.opacity(0.85)) }
        }
    }
}

struct RecipeCard: View {
    let r: Recipe
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecipeImage(data: r.image).frame(maxWidth: .infinity).frame(height: 120).clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(r.title).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                Text(r.m.kcal > 0 ? "\(Int(r.m.kcal)) kcal / portion · \(r.servings) pers." : "Valeurs nutritionnelles à compléter")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

struct RecipesView: View {
    @Environment(Store.self) var store
    @State private var filter = 0
    @State private var q = ""
    @State private var importing = false
    var shown: [Recipe] {
        store.recipes.filter { (filter == 0 || $0.cooked > 0) && (q.isEmpty || $0.title.localizedCaseInsensitiveContains(q)) }
            .sorted { filter == 1 ? ($0.lastCooked ?? .distantPast) > ($1.lastCooked ?? .distantPast) : $0.created > $1.created }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("", selection: $filter) { Text("Toutes").tag(0); Text("Déjà cuisinées").tag(1) }
                    .pickerStyle(.segmented).padding(.horizontal)
                if shown.isEmpty {
                    ContentUnavailableView("Aucune recette", systemImage: "book.closed", description: Text("Importez un lien contenant des données structurées ou collez le texte d’une recette."))
                        .padding(.top, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                    ForEach(shown) { r in
                        NavigationLink(value: r.id) { RecipeCard(r: r) }.buttonStyle(.plain)
                            .contextMenu { Button("Supprimer", systemImage: "trash", role: .destructive) { store.drop(r.id) } }
                    }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Recettes").searchable(text: $q)
            .navigationDestination(for: UUID.self) { RecipeDetail(id: $0) }
            .toolbar { Button { importing = true } label: { Image(systemName: "plus") } }
            .sheet(isPresented: $importing) { ImportView() }
        }
    }
}

struct RecipeDetail: View {
    let id: UUID
    @Environment(Store.self) var store
    @Environment(\.dismiss) var dismiss
    @State private var renaming = false
    @State private var deleting = false
    @State private var name = ""

    var body: some View {
        if let r = store.recipes.first(where: { $0.id == id }) { content(r) } else { Color.clear.onAppear { dismiss() } }
    }
    func chip(_ v: String, _ l: String, _ c: Color) -> some View {
        VStack(spacing: 2) { Text(v).font(.headline); Text(l).font(.caption2).foregroundStyle(.secondary) }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(c.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    func block<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(t).font(.title3.bold()); c() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .card(22)
    }
    func content(_ r: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RecipeImage(data: r.image).frame(maxWidth: .infinity).frame(height: 240).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                Text(r.title).font(.largeTitle.bold())
                if r.m.kcal > 0 {
                    HStack(spacing: 10) {
                        chip("\(Int(r.m.kcal))", "kcal", .green); chip("\(Int(r.m.p)) g", "protéines", .pink)
                        chip("\(Int(r.m.l)) g", "lipides", .orange); chip("\(Int(r.m.g)) g", "glucides", .blue)
                    }
                    Text("Valeurs par portion · \(r.servings) portion\(r.servings > 1 ? "s" : "")").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Valeurs nutritionnelles non disponibles. Les ingrédients et étapes sont enregistrés, sans inventer de calories.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                block("Ingrédients") { ForEach(r.ingredients, id: \.self) { Text("• \($0)") } }
                block("Préparation") {
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.footnote.bold()).frame(width: 24, height: 24).background(Color.green.opacity(0.2), in: Circle())
                            Text(s)
                        }
                    }
                }
                if r.m.kcal > 0 {
                    Menu {
                        ForEach(Meal.allCases) { m in
                            Button(m.title, systemImage: m.icon) { store.add(Entry(date: Date(), meal: m, name: r.title, detail: "1 portion", m: r.m, source: "Recette")) }
                        }
                    } label: { Label("Ajouter au journal", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Text("Ajout au journal indisponible tant que les valeurs nutritionnelles ne sont pas renseignées.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button { var x = r; x.cooked += 1; x.lastCooked = Date(); store.put(x) } label: {
                    Label(r.cooked > 0 ? "Cuisinée \(r.cooked) fois" : "Je l’ai cuisinée", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).controlSize(.large)
                if let u = r.url, let link = URL(string: u) { Link("Voir la source", destination: link).font(.footnote) }
            }.padding()
        }
        .background(Color(.systemGroupedBackground)).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Menu {
                Button("Renommer", systemImage: "pencil") { name = r.title; renaming = true }
                Button("Supprimer", systemImage: "trash", role: .destructive) { deleting = true }
            } label: { Image(systemName: "ellipsis.circle") }
        }
        .alert("Renommer", isPresented: $renaming) {
            TextField("Nom", text: $name)
            Button("OK") { var x = r; x.title = name; store.put(x) }
            Button("Annuler", role: .cancel) {}
        }
        .confirmationDialog("Supprimer cette recette ?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { store.drop(id) }
        }
    }
}

struct ImportView: View {
    @Environment(Store.self) var store
    @Environment(\.dismiss) var dismiss
    @State private var mode = 0
    @State private var text = ""
    @State private var busy = false
    @State private var err = ""

    func save(_ dto: RecipeDTO, image: Data?, url: String?) throws {
        guard let title = dto.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            throw AIError.bad(dto.error ?? "Titre de recette introuvable.")
        }
        guard let ingredients = dto.ingredients, !ingredients.isEmpty else {
            throw AIError.bad("La recette ne contient pas d’ingrédients exploitables.")
        }
        let nutritionComplete = dto.kcal != nil && dto.p != nil && dto.l != nil && dto.g != nil
        let macros = nutritionComplete
            ? Macros(kcal: dto.kcal!, p: dto.p!, l: dto.l!, g: dto.g!)
            : Macros()
        store.put(Recipe(
            title: title,
            servings: max(1, dto.servings ?? 1),
            ingredients: ingredients,
            steps: dto.steps ?? [],
            m: macros,
            image: image,
            url: url
        ))
        dismiss()
    }

    func run(_ operation: @escaping () async throws -> Void) {
        busy = true
        err = ""
        Task {
            do { try await operation() }
            catch { err = error.localizedDescription }
            busy = false
        }
    }

    func importContent() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        run {
            if value.lowercased().hasPrefix("https://") || value.lowercased().hasPrefix("http://") {
                let (dto, image) = try await Importer.fromURL(value)
                try save(dto, image: image, url: value)
            } else {
                let dto = try Importer.fromText(value)
                try save(dto, image: nil, url: nil)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) {
                    Text("Lien").tag(0)
                    Text("Texte").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                Section(mode == 0 ? "Lien de la recette" : "Texte de la recette") {
                    TextField(mode == 0 ? "https://…" : "Nom, ingrédients et préparation…", text: $text, axis: .vertical)
                        .lineLimit(4...10)
                    if mode == 0 {
                        Button("Coller depuis le presse-papiers") { text = UIPasteboard.general.string ?? text }
                    }
                    Button(mode == 0 ? "Importer la recette" : "Enregistrer la recette", action: importContent)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                } footer: {
                    if mode == 0 {
                        Text("Assiette lit les données structurées Recipe (JSON-LD) publiées par le site. Aucun compte ni service d’IA n’est nécessaire. Certains sites bloquent l’accès ou ne publient pas ces données.")
                    } else {
                        Text("Structure attendue : première ligne = titre, puis les sections « Ingrédients » et « Préparation ». Les valeurs nutritionnelles restent non renseignées tant qu’elles ne sont pas calculées à partir d’une base fiable.")
                    }
                }

                if busy {
                    HStack { ProgressView(); Text("Importation locale…").foregroundStyle(.secondary) }
                }
                if !err.isEmpty { Text(err).foregroundStyle(.red) }
            }
            .navigationTitle("Nouvelle recette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
