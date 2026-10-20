import Foundation

/// Ein Studienmodul, z. B. "Analysis I" mit Kürzel "MAT101".
struct StudyModule: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var code: String
    var color: ModuleColor
    var createdAt: Date
    /// Leistungspunkte (ECTS), falls bekannt.
    var credits: Double? = nil
    /// Endnote im deutschen System (1,0–5,0), falls schon vorhanden.
    var grade: Double? = nil
}
