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
    @State private var cands: [Cand] = []
    @State private var hits: [OFFResult] = []
    @State private var picked: OFFResult?
    @State private var grams = "100"
    @State private var photo: PhotosPickerItem?
    @State private var scanning = false
    @State private var cam = false
    @State private var searchTask: Task<Void
    @State private var Never>?

    func add(_ c: Cand) {
        store.add(Entry(date: day, meal: meal, name: c.name, detail: c.detail, m: c.m, source: c.source)); dismiss()
    }
    func run(_ job: @escaping () async throws -> Void) {
        busy = true; err = ""
        Task { do { try await job() } catch { err = error.localizedDescription }; busy = false }
    }
    func go() {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        run {
            if mode == 0 {
                async let off = (try? await FoodDB.search(q)) ?? []
                async let us = (try? await FoodDB.usda(q)) ?? []
                hits = Ciqual.search(q) + (await off) + (await us); cands = []; picked = nil
                if hits.isEmpty { err = "Aucun résultat. Les bases USDA sont en anglais." }
            } else { cands = try await AI.estimate(q, nil); hits = [] }
        }
    }
    func analyze(_ img: UIImage) {
        run { cands = try await AI.estimate(text, img); hits = [] }
    }
    func analyzeItem(_ item: PhotosPickerItem?) {
        guard let item else { return }
        run {
            guard let d = try await item.loadTransferable(type: Data.self), let img = UIImage(data: d) else { throw AIError.bad("Photo illisible.") }
            cands = try await AI.estimate(text, img); hits = []
        }
    }
    func lookup(_ code: String) {
        run {
            if let r = try await FoodDB.barcode(code) { hits = [r]; picked = r; cands = [] }
            else { err = "Produit introuvable dans Open Food Facts." }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $mode) { Text("Recherche").tag(0); Text("Photo").tag(1); Text("Texte").tag(2) }
                    .pickerStyle(.segmented).listRowBackground(Color.clear)
                if mode == 1 {
                    Button { cam = true } label: { Label("Prendre une photo du plat", systemImage: "camera.fill") }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choisir dans la photothèque", systemImage: "photo") }
                } else {
                    TextField(mode == 0 ? "Ex. haribo, yaourt grec, banane…" : "Ex. 2 œufs, 1 tranche de pain complet", text: $text).onSubmit(go)
                    Button(mode == 0 ? "Rechercher" : "Estimer", action: go).disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    if mode == 0 {
                        Button { scanning = true } label: { Label("Scanner un code-barres", systemImage: "barcode.viewfinder") }
                            .disabled(!DataScannerViewController.isSupported)
                    }
                }
                if busy { HStack { ProgressView(); Text("Analyse…").foregroundStyle(.secondary) } }
                if !err.isEmpty { Text(err).foregroundStyle(.red) }
                if let p = picked {
                    Section("Quantité") {
                        TextField("Grammes", text: $grams).keyboardType(.decimalPad)
                        Button("Ajouter \(p.name)") {
                            let q = Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 100
                            add(Cand(name: p.name, detail: "\(Int(q)) g", m: p.per100.scaled(q / 100), source: p.source))
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
                guard q.count >= 3 else { hits = []; return }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    guard !Task.isCancelled else { return }
                    let off = (try? await FoodDB.search(q)) ?? []
                    if !Task.isCancelled { hits = Ciqual.search(q) + off; cands = []; picked = nil }
                }
            }
            .fullScreenCover(isPresented: $cam) { CameraView { analyze($0) }.ignoresSafeArea() }
            .fullScreenCover(isPresented: $scanning) { ScannerSheet { code in scanning = false; lookup(code) } }
        }
    }
}
