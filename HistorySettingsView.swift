import SwiftUI
import Charts
import UniformTypeIdentifiers

struct DayKcal: Identifiable { let id: Date; let kcal: Double }
struct MacroSlice: Identifiable { let id: String; let v: Double }

struct HistoryView: View {
    @Environment(Store.self) var store
    var days: [Date] { Array(Set(store.entries.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }
    var weightMeasurements: [BodyMeasurement] {
        store.bodyMeasurements.filter { $0.weightKg != nil }.sorted { $0.date < $1.date }
    }
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
                if days.isEmpty && store.bodyMeasurements.isEmpty {
                    ContentUnavailableView("Rien pour l’instant", systemImage: "clock", description: Text("Vos repas et mesures corporelles apparaîtront ici."))
                }
                if weightMeasurements.isEmpty == false {
                    Section("Évolution du poids") {
                        Chart {
                            ForEach(weightMeasurements) { measurement in
                                if let weight = measurement.weightKg {
                                    LineMark(x: .value("Date", measurement.date), y: .value("Poids", weight))
                                        .interpolationMethod(.catmullRom)
                                    PointMark(x: .value("Date", measurement.date), y: .value("Poids", weight))
                                }
                            }
                        }
                        .chartYAxisLabel("kg")
                        .frame(height: 180)
                        if let first = weightMeasurements.first?.weightKg,
                           let latest = weightMeasurements.last?.weightKg {
                            let delta = latest - first
                            Text(String(format: "Évolution sur la période : %+.1f kg", delta))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !days.isEmpty {
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
    @State private var wipe = false
    @State private var importing = false
    @State private var nCiqual = Ciqual.rows.count
    @State private var ciqualError = ""
    @State private var heightText = ""
    @State private var ageText = ""
    @State private var targetWeightText = ""
    @State private var targetFatText = ""
    @State private var currentWeightText = ""
    @State private var waistText = ""
    @State private var chestText = ""
    @State private var armText = ""
    @State private var sex: BiologicalSex = .male
    @State private var activity: ActivityLevel = .sedentary
    @State private var measurementDate = Date()
    var latestWeight: Double? { store.bodyMeasurements.first(where: { $0.weightKg != nil })?.weightKg }
    var maintenanceEstimate: Double? { store.bodyProfile.estimatedMaintenanceCalories(weightKg: latestWeight) }
    func number(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines))
    }
    func loadProfileFields() {
        heightText = store.bodyProfile.heightCm.map { String(format: "%.1f", $0) } ?? ""
        ageText = store.bodyProfile.ageYears.map(String.init) ?? ""
        targetWeightText = store.bodyGoals.targetWeightKg.map { String(format: "%.1f", $0) } ?? ""
        targetFatText = store.bodyGoals.targetBodyFatPercentage.map { String(format: "%.1f", $0) } ?? ""
        sex = store.bodyProfile.sex ?? .male
        activity = store.bodyProfile.activityLevel ?? .sedentary
    }
    var body: some View {
        @Bindable var s = store
        NavigationStack {
            Form {
                Section("Profil corporel") {
                    TextField("Taille (cm)", text: $heightText).keyboardType(.decimalPad)
                    TextField("Âge (ans)", text: $ageText).keyboardType(.numberPad)
                    Picker("Sexe utilisé pour la formule", selection: $sex) {
                        ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Activité quotidienne", selection: $activity) {
                        ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Poids cible (kg)", text: $targetWeightText).keyboardType(.decimalPad)
                    TextField("Masse grasse cible (%)", text: $targetFatText).keyboardType(.decimalPad)
                    Button("Enregistrer le profil") {
                        store.bodyProfile.heightCm = number(heightText)
                        store.bodyProfile.ageYears = Int(ageText)
                        store.bodyProfile.sex = sex
                        store.bodyProfile.activityLevel = activity
                        store.bodyGoals.targetWeightKg = number(targetWeightText)
                        store.bodyGoals.targetBodyFatPercentage = number(targetFatText)
                        store.save()
                    }
                    if let kcal = maintenanceEstimate {
                        Text("Maintien estimé : environ \(Int(kcal.rounded())) kcal/jour")
                            .font(.subheadline.weight(.semibold))
                        Text("Estimation Mifflin–St Jeor selon le dernier poids enregistré et le niveau d’activité choisi. Ce n’est pas une mesure.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Utiliser comme objectif calorique") {
                            s.goal.kcal = kcal.rounded()
                            store.save()
                        }
                    } else {
                        Text("Enregistrez un poids et complétez taille, âge, sexe et activité pour obtenir une estimation.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Nouvelle mesure") {
                    DatePicker("Date", selection: $measurementDate, displayedComponents: .date)
                    TextField("Poids (kg)", text: $currentWeightText).keyboardType(.decimalPad)
                    TextField("Tour de taille (cm)", text: $waistText).keyboardType(.decimalPad)
                    TextField("Tour de poitrine (cm)", text: $chestText).keyboardType(.decimalPad)
                    TextField("Tour de bras (cm)", text: $armText).keyboardType(.decimalPad)
                    Button("Enregistrer la mesure") {
                        store.addBodyMeasurement(BodyMeasurement(
                            date: measurementDate,
                            weightKg: number(currentWeightText),
                            waistCm: number(waistText),
                            chestCm: number(chestText),
                            armCm: number(armText)
                        ))
                        currentWeightText = ""
                        waistText = ""
                        chestText = ""
                        armText = ""
                        measurementDate = Date()
                    }
                    .disabled([currentWeightText, waistText, chestText, armText].allSatisfy { number($0) == nil })
                }
                if !store.bodyMeasurements.isEmpty {
                    Section("Mesures récentes") {
                        ForEach(store.bodyMeasurements.prefix(8)) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(frDate(item.date, "d MMM yyyy"))
                                    .font(.subheadline.weight(.medium))
                                Text([
                                    item.weightKg.map { String(format: "Poids %.1f kg", $0) },
                                    item.waistCm.map { String(format: "Taille %.1f cm", $0) },
                                    item.chestCm.map { String(format: "Poitrine %.1f cm", $0) },
                                    item.armCm.map { String(format: "Bras %.1f cm", $0) }
                                ].compactMap { $0 }.joined(separator: " · "))
                                .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { offsets in
                            let recent = Array(store.bodyMeasurements.prefix(8))
                            store.removeBodyMeasurements(offsets.map { recent[$0].id })
                        }
                    }
                }
                Section("Objectifs quotidiens") {
                    Stepper("Calories : \(Int(s.goal.kcal)) kcal", value: $s.goal.kcal, in: 1000...5000, step: 50)
                    Stepper("Protéines : \(Int(s.goal.p)) g", value: $s.goal.p, in: 20...400, step: 5)
                    Stepper("Lipides : \(Int(s.goal.l)) g", value: $s.goal.l, in: 20...300, step: 5)
                    Stepper("Glucides : \(Int(s.goal.g)) g", value: $s.goal.g, in: 20...600, step: 5)
                }
                Section("Reconnaissance") {
                    Text("La reconnaissance photo actuelle fonctionne localement avec Apple Vision. Elle propose des aliments probables, mais ne segmente pas encore les ingrédients d’un plat composé et ne mesure pas les portions.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Link("Télécharger la table officielle Ciqual 2025", destination: URL(string: "https://entrepot.recherche.data.gouv.fr/dataset.xhtml?persistentId=doi%3A10.57745%2FRDMHWY")!)
                    Button("Importer le fichier CIQUAL (.csv)") { importing = true }
                    Text(nCiqual > 0 ? "CIQUAL chargé : \(nCiqual) aliments" : "CIQUAL non chargé").font(.footnote).foregroundStyle(.secondary)
                    if !ciqualError.isEmpty { Text(ciqualError).font(.footnote).foregroundStyle(.red) }
                } header: { Text("Bases alimentaires") } footer: {
                    Text("CIQUAL 2025 est la base française de référence. Exportez l’onglet « composition nutritionnelle » en CSV UTF-8 avant l’import. Données : Anses, Table de composition nutritionnelle des aliments Ciqual 2025 — Licence Ouverte 2.0.")
                }
                Section("Données") { Button("Effacer tout le journal", role: .destructive) { wipe = true } }
            }
            .navigationTitle("Réglages")
            .onAppear(perform: loadProfileFields)
            .onChange(of: s.goal) { _, _ in store.save() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { r in
                switch r {
                case .success(let url):
                    do { try Ciqual.importFile(url); nCiqual = Ciqual.rows.count; ciqualError = "" }
                    catch { nCiqual = Ciqual.rows.count; ciqualError = error.localizedDescription }
                case .failure(let error): ciqualError = error.localizedDescription
                }
            }
            .confirmationDialog("Effacer tout le journal ?", isPresented: $wipe, titleVisibility: .visible) {
                Button("Effacer", role: .destructive) { store.entries = []; store.save() }
            }
        }
    }
}
