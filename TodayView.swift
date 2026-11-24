import SwiftUI
import PhotosUI

struct Ring: View {
    let value: Double, goal: Double
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: 14)
            Circle().trim(from: 0, to: min(1, value / max(goal, 1)))
                .stroke(value > goal ? Color.orange : Color.green, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90)).animation(.spring, value: value)
        }
    }
}

struct MacroBar: View {
    let name: String, v: Double, goal: Double, color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name).font(.subheadline.weight(.medium)); Spacer()
                Text("\(Int(v)) / \(Int(goal)) g").font(.footnote).foregroundStyle(.secondary)
            }
            ProgressView(value: min(v, goal), total: max(goal, 1)).tint(color)
        }
    }
}

struct TodayView: View {
    @Environment(Store.self) var store
    @State private var day = Date()
    @State private var adding: Meal?
    @State private var savingMeal = false
    @State private var mealName = ""
    @State private var mealToSave: Meal?

    func shift(_ n: Int) { day = Calendar.current.date(byAdding: .day, value: n, to: day) ?? day }

    @ViewBuilder var summary: some View {
        let t = store.total(day), g = store.goal
        HStack(spacing: 22) {
            Ring(value: t.kcal, goal: g.kcal).frame(width: 128, height: 128).overlay {
                VStack(spacing: 0) {
                    Text("\(Int(abs(g.kcal - t.kcal)))").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(g.kcal >= t.kcal ? "kcal restantes" : "kcal en trop").font(.caption2).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 12) {
                MacroBar(name: "Protéines", v: t.p, goal: g.p, color: .pink)
                MacroBar(name: "Lipides", v: t.l, goal: g.l, color: .orange)
                MacroBar(name: "Glucides", v: t.g, goal: g.g, color: .blue)
            }
        }
        .padding(18)
        .card(24)
    }

    func mealHeader(_ m: Meal) -> some View {
        HStack {
            Label(m.title, systemImage: m.icon).foregroundStyle(m.color)
            Spacer()
            Text("\(Int(store.total(day, m).kcal)) kcal").foregroundStyle(.secondary)
        }
        .font(.headline)
        .textCase(nil)
    }

    func entryRow(_ e: Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.name).font(.body.weight(.medium))
            Text(e.detail + "  " + e.m.line).font(.footnote).foregroundStyle(.secondary)
        }
    }

    func mealSection(_ m: Meal) -> some View {
        let items: [Entry] = store.list(day, m)
        return Section {
            ForEach(items) { e in entryRow(e) }
                .onDelete { offsets in store.remove(offsets.map { items[$0].id }) }
            Button { adding = m } label: { Label("Ajouter", systemImage: "plus.circle.fill") }
            if !items.isEmpty {
                Button {
                    mealToSave = m
                    mealName = "\(m.title) habituel"
                    savingMeal = true
                } label: {
                    Label("Enregistrer comme repas", systemImage: "bookmark")
                }
            }
        } header: {
            mealHeader(m)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { summary.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }
                ForEach(Meal.allCases) { m in mealSection(m) }
            }
            .navigationTitle(Calendar.current.isDateInToday(day) ? "Aujourd’hui" : frDate(day, "EEEE d MMM"))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
            }
            .sheet(item: $adding) { AddFoodView(meal: $0, day: day) }
            .alert("Enregistrer ce repas", isPresented: $savingMeal) {
                TextField("Nom du repas", text: $mealName)
                Button("Enregistrer") {
                    guard let selectedMeal = mealToSave else { return }
                    let items = store.list(day, selectedMeal).map {
                        SavedMealItem(name: $0.name, detail: $0.detail, m: $0.m, source: $0.source)
                    }
                    let title = mealName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty, !items.isEmpty else { return }
                    store.put(SavedMeal(title: title, items: items))
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Le contenu de ce repas sera conservé dans votre bibliothèque et pourra être ajouté en une fois.")
            }

        }
    }
}

