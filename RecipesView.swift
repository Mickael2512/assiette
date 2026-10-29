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
                Text("\(Int(r.m.kcal)) kcal · \(r.servings) pers.").font(.caption).foregroundStyle(.secondary)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

struct RecipesView: View {
    @Environment(Store.self) var store
    @State private var filter = 0, q = "", importing = false
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
                    ContentUnavailableView("Aucune recette", systemImage: "book.closed", description: Text("Importez un lien, une photo de livre ou demandez une idée avec votre frigo."))
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
    @State private var renaming = false, deleting = false, name = ""

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
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    func content(_ r: Recipe) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                RecipeImage(data: r.image).frame(maxWidth: .infinity).frame(height: 240).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                Text(r.title).font(.largeTitle.bold())
                HStack(spacing: 10) {
                    chip("\(Int(r.m.kcal))", "kcal", .green); chip("\(Int(r.m.p)) g", "protéines", .pink)
                    chip("\(Int(r.m.l)) g", "lipides", .orange); chip("\(Int(r.m.g)) g", "glucides", .blue)
                }
                Text("Valeurs par portion · \(r.servings) portion\(r.servings > 1 ? "s" : "")").font(.footnote).foregroundStyle(.secondary)
                block("Ingrédients") { ForEach(r.ingredients, id: \.self) { Text("• \($0)") } }
                block("Préparation") {
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(i + 1)").font(.footnote.bold()).frame(width: 24, height: 24).background(Color.green.opacity(0.2), in: Circle())
                            Text(s)
                        }
                    }
                }
                Menu {
                    ForEach(Meal.allCases) { m in
                        Button(m.title, systemImage: m.icon) { store.add(Entry(date: Date(), meal: m, name: r.title, detail: "1 portion", m: r.m, source: "Recette")) }
                    }
                } label: { Label("Ajouter au journal", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
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
    @State private var mode = 0, text = "", meal = Meal.dinner, busy = false, err = ""
    @State private var photo: PhotosPickerItem?
    @State private var cam = false

    func bookImage(_ img: UIImage) {
        run {
            let dto = try await AI.json(RecipeDTO.self, prompt: "Lis la recette sur cette photo de livre. " + Importer.fmt, image: img)
            try await save(dto, img.resized(900).jpegData(compressionQuality: 0.8), nil)
        }
    }

    func save(_ d: RecipeDTO, _ img: Data?, _ url: String?) async throws {
        var d = d
        if (d.kcal ?? 0) == 0, let ings = d.ingredients, !ings.isEmpty {
            struct Est: Decodable { var kcal: Double?; var p: Double?; var l: Double?; var g: Double? }
            let q = "Estime les valeurs nutritionnelles PAR PORTION (\(d.servings ?? 2) portions) de cette recette : " + ings.joined(separator: " ; ") + ". JSON uniquement : {\"kcal\":0,\"p\":0,\"l\":0,\"g\":0}, nombres seuls, jamais 0."
            if let m = try? await AI.json(Est.self, prompt: q) { d.kcal = m.kcal; d.p = m.p; d.l = m.l; d.g = m.g }
        }
        guard let t = d.title, !t.isEmpty else { throw AIError.bad(d.error ?? "Recette introuvable. Collez la description du lien.") }
        store.put(Recipe(title: t, servings: max(1, d.servings ?? 2), ingredients: d.ingredients ?? [], steps: d.steps ?? [],
                         m: Macros(kcal: d.kcal ?? 0, p: d.p ?? 0, l: d.l ?? 0, g: d.g ?? 0), image: img, url: url))
        dismiss()
    }
    func run(_ job: @escaping () async throws -> Void) {
        busy = true; err = ""
        Task { do { try await job() } catch { err = error.localizedDescription }; busy = false }
    }
    func importText() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        run {
            if t.lowercased().hasPrefix("http"), !t.contains(" ") {
                let (d, img) = try await Importer.fromURL(t); try await save(d, img, t)
            } else { try await save(try await AI.json(RecipeDTO.self, prompt: Importer.prompt(t)), nil, nil) }
        }
    }
    func fridge() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        run { try await save(try await AI.json(RecipeDTO.self, prompt: "Invente une recette de \(meal.title.lowercased()) simple et gourmande avec principalement : \(t). Tu peux ajouter des basiques (huile, sel, épices). " + Importer.fmt), nil, nil) }
    }
    func book(_ item: PhotosPickerItem?) {
        guard let item else { return }
        run {
            guard let d = try await item.loadTransferable(type: Data.self), let img = UIImage(data: d) else { throw AIError.bad("Photo illisible.") }
            let dto = try await AI.json(RecipeDTO.self, prompt: "Lis la recette sur cette photo de livre. " + Importer.fmt, image: img)
            try await save(dto, img.resized(900).jpegData(compressionQuality: 0.8), nil)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) { Text("Lien").tag(0); Text("Photo").tag(1); Text("Frigo").tag(2) }
                    .pickerStyle(.segmented).listRowBackground(Color.clear)
                if mode == 0 {
                    Section {
                        TextField("Lien ou texte de la recette", text: $text, axis: .vertical).lineLimit(3...8)
                        Button("Coller depuis le presse-papiers") { text = UIPasteboard.general.string ?? text }
                        Button("Importer", action: importText).disabled(text.isEmpty || busy)
                    } footer: { Text("Instagram, TikTok, blogs… Si le lien est bloqué, collez la description de la publication.") }
                }
                if mode == 1 {
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choisir la photo d’une page de livre", systemImage: "book") }
                    Button { cam = true } label: { Label("Prendre une photo", systemImage: "camera.fill") }
                }
                if mode == 2 {
                    Section("Ce que vous avez") {
                        TextField("Ex. poulet, riz, courgettes, crème…", text: $text, axis: .vertical).lineLimit(3...8)
                        Picker("Repas", selection: $meal) { ForEach(Meal.allCases) { Text($0.title).tag($0) } }
                        Button("Créer une recette", action: fridge).disabled(text.isEmpty || busy)
                    }
                }
                if busy { HStack { ProgressView(); Text("L’IA prépare votre recette…").foregroundStyle(.secondary) } }
                if !err.isEmpty { Text(err).foregroundStyle(.red) }
            }
            .navigationTitle("Nouvelle recette").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .onChange(of: photo) { _, item in book(item) }
            .fullScreenCover(isPresented: $cam) { CameraView { bookImage($0) }.ignoresSafeArea() }
        }
    }
}
