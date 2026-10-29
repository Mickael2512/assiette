import SwiftUI
import Charts
import UniformTypeIdentifiers

struct DayKcal: Identifiable { let id: Date; let kcal: Double }
struct MacroSlice: Identifiable { let id: String; let v: Double }

struct HistoryView: View {
    @Environment(Store.self) var store
    var days: [Date] { Array(Set(store.entries.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }
    var week: [DayKcal] {
        (0..<7).reversed().map { i in
            let d = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -i, to: Date())!)
            return DayKcal(id: d, kcal: store.total(d).kcal)
        }
    }
    var split: [MacroSlice] {
        let t = week.reduce(Macros()) { $0 + store.total($1.id) }
        return [MacroSlice(id: "Protéines", v: t.p), MacroSlice(id: "Lipides", v: t.l), MacroSlice(id: "Glucides", v: t.g)]
    }
    var body: some View {
        NavigationStack {
            List {
                if days.isEmpty {
                    ContentUnavailableView("Rien pour l’instant", systemImage: "clock", description: Text("Vos repas apparaîtront ici, jour par jour."))
                } else {
                    Section("Calories, 7 derniers jours") {
                        Chart {
                            ForEach(week) { w in
                                BarMark(x: .value("Jour", w.id, unit: .day), y: .value("kcal", w.kcal))
                                    .foregroundStyle(w.kcal > store.goal.kcal ? Color.orange : Color.green).cornerRadius(5)
                            }
                            RuleMark(y: .value("Objectif", store.goal.kcal)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary)
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        .frame(height: 160)
                    }
                    Section("Répartition des macros, 7 jours") {
                        Chart(split) { s in
                            SectorMark(angle: .value("g", s.v), innerRadius: .ratio(0.62), angularInset: 2).foregroundStyle(by: .value("Macro", s.id)).cornerRadius(4)
                        }
                        .chartForegroundStyleScale(["Protéines": Color.pink, "Lipides": Color.orange, "Glucides": Color.blue])
                        .frame(height: 170)
                    }
                }
                ForEach(days, id: \.self) { d in
                    Section {
                        ForEach(Meal.allCases) { m in
                            let items = store.list(d, m)
                            if !items.isEmpty {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: m.icon).foregroundStyle(m.color).frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.title).font(.subheadline.weight(.semibold))
                                        Text(items.map(\.name).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(store.total(d, m).kcal))").font(.footnote.monospacedDigit())
                                }
                            }
                        }
                    } header: {
                        HStack { Text(frDate(d, "EEEE d MMMM")); Spacer(); Text("\(Int(store.total(d).kcal)) kcal") }.textCase(nil)
                    }
                }
            }.navigationTitle("Historique")
        }
    }
}

struct SettingsView: View {
    @Environment(Store.self) var store
    @AppStorage("geminiKey") private var gem = ""
    @AppStorage("geminiModel") private var model = "gemini-2.5-flash"
    @AppStorage("usdaKey") private var usda = ""
    @State private var wipe = false
    @State private var importing = false
    @State private var nCiqual = Ciqual.rows.count
    var body: some View {
        @Bindable var s = store
        NavigationStack {
            Form {
                Section("Objectifs quotidiens") {
                    Stepper("Calories : \(Int(s.goal.kcal)) kcal", value: $s.goal.kcal, in: 1000...5000, step: 50)
                    Stepper("Protéines : \(Int(s.goal.p)) g", value: $s.goal.p, in: 20...400, step: 5)
                    Stepper("Lipides : \(Int(s.goal.l)) g", value: $s.goal.l, in: 20...300, step: 5)
                    Stepper("Glucides : \(Int(s.goal.g)) g", value: $s.goal.g, in: 20...600, step: 5)
                }
                Section {
                    SecureField("Clé API Gemini (gratuite)", text: $gem).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Modèle", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Intelligence artificielle") } footer: {
                    Text("Gratuit : créez une clé sur aistudio.google.com avec un compte Google. Le palier gratuit est limité en débit et Google peut utiliser les textes et photos envoyés.")
                }
                Section {
                    SecureField("Clé USDA (optionnelle)", text: $usda).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Importer le fichier CIQUAL (.csv)") { importing = true }
                    Text(nCiqual > 0 ? "CIQUAL chargé : \(nCiqual) aliments" : "CIQUAL non chargé").font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Bases alimentaires") } footer: {
                    Text("Open Food Facts et USDA sont interrogées en ligne. Pour CIQUAL, téléchargez la table sur ciqual.anses.fr et enregistrez-la en CSV.")
                }
                Section("Données") { Button("Effacer tout le journal", role: .destructive) { wipe = true } }
            }
            .navigationTitle("Réglages")
            .onChange(of: s.goal) { _, _ in store.save() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { r in
                if case .success(let u) = r { try? Ciqual.importFile(u); nCiqual = Ciqual.rows.count }
            }
            .confirmationDialog("Effacer tout le journal ?", isPresented: $wipe, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { store.entries = []; store.save() }
            }
        }
    }
}
