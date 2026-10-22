import Foundation

/// Ein Studienmodul, z. B. "Analysis I" mit Kürzel "MAT101".
struct StudyModule: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var code: String
    var color: ModuleColor
    var createdAt: Date
    /// Leistungspunkte (ECTS), falls bekannt.
    var credits: Double?
    /// Endnote im deutschen System (1,0–5,0), falls schon vorhanden.
    var grade: Double?
    /// Semester, in dem das Modul belegt wird. Ohne Angabe das Semester des Anlegens.
    var semester: Semester
    /// Archivierte Module verschwinden aus Seitenleiste und Startseite, zählen aber weiter zum Notenschnitt.
    var isArchived: Bool
    /// Verknüpfte Stud.IP-Veranstaltung, aus der Folien geladen werden.
    var studIPCourseID: String?

    init(
        id: UUID,
        name: String,
        code: String,
        color: ModuleColor,
        createdAt: Date,
        credits: Double? = nil,
        grade: Double? = nil,
        semester: Semester? = nil,
        isArchived: Bool = false,
        studIPCourseID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.color = color
        self.createdAt = createdAt
        self.credits = credits
        self.grade = grade
        self.semester = semester ?? Semester(containing: createdAt)
        self.isArchived = isArchived
        self.studIPCourseID = studIPCourseID
    }
}
