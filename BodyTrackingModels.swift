import Foundation

/// Origine d'une mesure : permet de distinguer une donnée observée d'une estimation.
enum MeasurementSource: String, Codable, CaseIterable, Identifiable {
    case manual
    case scale
    case healthKit
    case imported
    case estimated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Saisie manuelle"
        case .scale: return "Balance connectée"
        case .healthKit: return "Apple Santé"
        case .imported: return "Importation"
        case .estimated: return "Estimation"
        }
    }

    var isEstimated: Bool { self == .estimated }
}

/// Une entrée peut contenir plusieurs mesures prises au même moment.
/// Les valeurs restent optionnelles : on ne crée pas de fausses données pour compléter une fiche.
struct BodyMeasurement: Codable, Identifiable, Hashable {
    var id: UUID
    var date: Date
    var weightKg: Double?
    var bodyFatPercentage: Double?
    var muscleMassKg: Double?
    var waistCm: Double?
    var chestCm: Double?
    var armCm: Double?
    var thighCm: Double?
    var hipCm: Double?
    var source: MeasurementSource
    var note: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        weightKg: Double? = nil,
        bodyFatPercentage: Double? = nil,
        muscleMassKg: Double? = nil,
        waistCm: Double? = nil,
        chestCm: Double? = nil,
        armCm: Double? = nil,
        thighCm: Double? = nil,
        hipCm: Double? = nil,
        source: MeasurementSource = .manual,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercentage = bodyFatPercentage
        self.muscleMassKg = muscleMassKg
        self.waistCm = waistCm
        self.chestCm = chestCm
        self.armCm = armCm
        self.thighCm = thighCm
        self.hipCm = hipCm
        self.source = source
        self.note = note
    }

    var hasValues: Bool {
        [weightKg, bodyFatPercentage, muscleMassKg, waistCm, chestCm, armCm, thighCm, hipCm]
            .contains { $0 != nil }
    }

    /// IMC calculé à partir du poids mesuré et de la taille du profil.
    /// Il n'est jamais enregistré comme une mesure.
    func bmi(heightCm: Double?) -> Double? {
        guard let weightKg, let heightCm, weightKg > 0, heightCm > 0 else { return nil }
        let heightM = heightCm / 100
        return weightKg / (heightM * heightM)
    }
}

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case female, male
    var id: String { rawValue }
    var title: String { self == .female ? "Femme" : "Homme" }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, high, veryHigh
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sedentary: return "Sédentaire"
        case .light: return "Légèrement actif"
        case .moderate: return "Modérément actif"
        case .high: return "Très actif"
        case .veryHigh: return "Extrêmement actif"
        }
    }
    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .high: return 1.725
        case .veryHigh: return 1.9
        }
    }
}

/// Informations stables nécessaires à une estimation énergétique.
struct BodyProfile: Codable, Hashable {
    var heightCm: Double?
    var ageYears: Int?
    var sex: BiologicalSex?
    var activityLevel: ActivityLevel?

    init(heightCm: Double? = nil, ageYears: Int? = nil, sex: BiologicalSex? = nil, activityLevel: ActivityLevel? = nil) {
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.sex = sex
        self.activityLevel = activityLevel
    }

    /// Estimation Mifflin-St Jeor × facteur d'activité. Ce n'est pas une mesure.
    func estimatedMaintenanceCalories(weightKg: Double?) -> Double? {
        guard let weightKg, weightKg > 0, let heightCm, heightCm > 0,
              let ageYears, ageYears > 0, let sex, let activityLevel else { return nil }
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears) + (sex == .male ? 5 : -161)
        return max(0, base * activityLevel.multiplier)
    }
}

/// Objectifs corporels distincts des mesures réellement enregistrées.
struct BodyGoals: Codable, Hashable {
    var targetWeightKg: Double?
    var targetBodyFatPercentage: Double?
    var weeklyWeightChangeKg: Double?

    init(targetWeightKg: Double? = nil, targetBodyFatPercentage: Double? = nil, weeklyWeightChangeKg: Double? = nil) {
        self.targetWeightKg = targetWeightKg
        self.targetBodyFatPercentage = targetBodyFatPercentage
        self.weeklyWeightChangeKg = weeklyWeightChangeKg
    }
}
