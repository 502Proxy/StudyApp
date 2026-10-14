import Foundation

/// Ein Studienmodul, z. B. "Analysis I" mit Kürzel "MAT101".
struct StudyModule: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var code: String
    var color: ModuleColor
    var createdAt: Date
}
