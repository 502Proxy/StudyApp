import Foundation
import SwiftData

@Model
final class StudySheetRecord {
    @Attribute(.unique) var id: UUID
    var moduleID: UUID
    var title: String
    var content: String
    /// UUIDs are stored as delimited text to keep the SwiftData schema migration simple.
    var sourceNoteIDsRaw: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        moduleID: UUID,
        title: String,
        content: String,
        sourceNoteIDsRaw: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.content = content
        self.sourceNoteIDsRaw = sourceNoteIDsRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension StudySheetRecord {
    convenience init(_ sheet: StudySheet) {
        self.init(
            id: sheet.id,
            moduleID: sheet.moduleID,
            title: sheet.title,
            content: sheet.content,
            sourceNoteIDsRaw: sheet.sourceNoteIDs.map(\.uuidString).joined(separator: ","),
            createdAt: sheet.createdAt,
            updatedAt: sheet.updatedAt
        )
    }

    func toDomain() -> StudySheet {
        let sourceIDs = sourceNoteIDsRaw
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0)) }
        return StudySheet(
            id: id,
            moduleID: moduleID,
            title: title,
            content: content,
            sourceNoteIDs: sourceIDs,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(_ sheet: StudySheet) {
        title = sheet.title
        content = sheet.content
        sourceNoteIDsRaw = sheet.sourceNoteIDs.map(\.uuidString).joined(separator: ",")
        updatedAt = sheet.updatedAt
    }
}
