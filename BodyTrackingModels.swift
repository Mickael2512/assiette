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

/// Informations stables utilisées pour contextualiser les mesures corporelles.
struct BodyProfile: Codable, Hashable {
    var heightCm: Double?

    init(heightCm: Double? = nil) {
        self.heightCm = heightCm
    }
}

/// Objectifs corporels distincts des mesures réellement enregistrées.
struct BodyGoals: Codable, Hashable {
    var targetWeightKg: Double?
    var targetBodyFatPercentage: Double?

    init(targetWeightKg: Double? = nil, targetBodyFatPercentage: Double? = nil) {
        self.targetWeightKg = targetWeightKg
        self.targetBodyFatPercentage = targetBodyFatPercentage
    }
}
