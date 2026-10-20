import Foundation

enum GradeError: Error, Equatable, LocalizedError {
    case invalidGrade
    case invalidCredits

    var errorDescription: String? {
        switch self {
        case .invalidGrade: "Die Note muss zwischen 1,0 und 5,0 liegen."
        case .invalidCredits: "Die Leistungspunkte müssen zwischen 0 und 60 liegen."
        }
    }
}

/// Deutsches Notensystem: 1,0 (sehr gut) bis 5,0 (nicht bestanden), bestanden bis einschließlich 4,0.
enum GradeScale {
    static let best = 1.0
    static let worstPassing = 4.0
    static let failing = 5.0
    static let range = best...failing
    static let maximumCredits = 60.0

    static func isPassing(_ grade: Double) -> Bool {
        grade <= worstPassing + 0.000_1
    }

    /// Liest Eingaben wie „1,7“, „2.3“ oder leeren Text (`nil`).
    static func parse(_ text: String) -> Double?? {
        let cleaned = text.trimmed.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return .some(nil) }
        guard let value = Double(cleaned) else { return nil }
        return .some(value)
    }

    /// „1,7“ mit deutschem Komma und einer Nachkommastelle.
    static func format(_ grade: Double) -> String {
        String(format: "%.1f", grade).replacingOccurrences(of: ".", with: ",")
    }

    static func formatCredits(_ credits: Double) -> String {
        credits.rounded() == credits
            ? String(Int(credits))
            : String(format: "%.1f", credits).replacingOccurrences(of: ".", with: ",")
    }
}

/// Kennzahlen des Studiums über alle Module.
struct GradeSummary: Equatable, Sendable {
    /// Nach Leistungspunkten gewichteter Schnitt aller bestandenen benoteten Module.
    let weightedAverage: Double?
    /// Leistungspunkte aller bestandenen Module.
    let earnedCredits: Double
    /// Leistungspunkte aller Module mit hinterlegten ECTS.
    let plannedCredits: Double
    let gradedModuleCount: Int
    let failedModuleCount: Int

    init(modules: [StudyModule]) {
        var weightedSum = 0.0
        var weightSum = 0.0
        var earned = 0.0
        var planned = 0.0
        var graded = 0
        var failed = 0
        for module in modules {
            let credits = module.credits ?? 0
            planned += credits
            guard let grade = module.grade else { continue }
            graded += 1
            guard GradeScale.isPassing(grade) else {
                failed += 1
                continue
            }
            earned += credits
            if credits > 0 {
                weightedSum += grade * credits
                weightSum += credits
            }
        }
        weightedAverage = weightSum > 0 ? weightedSum / weightSum : nil
        earnedCredits = earned
        plannedCredits = planned
        gradedModuleCount = graded
        failedModuleCount = failed
    }
}

/// Speichert Note und Leistungspunkte eines Moduls; `nil` entfernt den Wert.
@MainActor
struct UpdateModuleGradeUseCase {
    let repository: any ModuleRepository

    @discardableResult
    func callAsFunction(_ module: StudyModule, credits: Double?, grade: Double?) throws -> StudyModule {
        if let grade, !GradeScale.range.contains(grade) { throw GradeError.invalidGrade }
        if let credits, !(0...GradeScale.maximumCredits).contains(credits) { throw GradeError.invalidCredits }
        var updated = module
        updated.credits = credits
        // Noten werden auf eine Nachkommastelle gerundet, wie im Zeugnis.
        updated.grade = grade.map { ($0 * 10).rounded() / 10 }
        guard updated != module else { return module }
        try repository.update(updated)
        return updated
    }
}
