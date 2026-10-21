import Foundation
import SwiftData

/// SwiftData-Modell. Bleibt in der Data-Schicht, die Domain sieht nur `StudyModule`.
@Model
final class ModuleRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var code: String
    var colorRaw: String
    var createdAt: Date
    /// Optional, damit bestehende Datenbanken per leichtgewichtiger Migration übernommen werden.
    var credits: Double?
    var grade: Double?
    /// `Semester.rawValue`, z. B. „2025W“. Fehlt bei älteren Datensätzen.
    var semesterRaw: String?
    var isArchived: Bool?
    var studIPCourseID: String?

    init(
        id: UUID, name: String, code: String, colorRaw: String, createdAt: Date,
        credits: Double? = nil, grade: Double? = nil,
        semesterRaw: String? = nil, isArchived: Bool? = nil, studIPCourseID: String? = nil
    ) {
        self.id = id
        self.name = name
        self.code = code
        self.colorRaw = colorRaw
        self.createdAt = createdAt
        self.credits = credits
        self.grade = grade
        self.semesterRaw = semesterRaw
        self.isArchived = isArchived
        self.studIPCourseID = studIPCourseID
    }
}

extension ModuleRecord {
    convenience init(_ module: StudyModule) {
        self.init(
            id: module.id,
            name: module.name,
            code: module.code,
            colorRaw: module.color.rawValue,
            createdAt: module.createdAt,
            credits: module.credits,
            grade: module.grade,
            semesterRaw: module.semester.rawValue,
            isArchived: module.isArchived,
            studIPCourseID: module.studIPCourseID
        )
    }

    func toDomain() -> StudyModule {
        StudyModule(
            id: id,
            name: name,
            code: code,
            color: ModuleColor(rawValue: colorRaw) ?? .violet,
            createdAt: createdAt,
            credits: credits,
            grade: grade,
            semester: semesterRaw.flatMap(Semester.init(rawValue:)),
            isArchived: isArchived ?? false,
            studIPCourseID: studIPCourseID
        )
    }

    func apply(_ module: StudyModule) {
        name = module.name
        code = module.code
        colorRaw = module.color.rawValue
        credits = module.credits
        grade = module.grade
        semesterRaw = module.semester.rawValue
        isArchived = module.isArchived
        studIPCourseID = module.studIPCourseID
    }
}
