import Foundation

/// A structured, editable learning sheet compiled from selected lecture notes.
struct StudySheet: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let moduleID: UUID
    var title: String
    var content: String
    var sourceNoteIDs: [UUID]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        moduleID: UUID,
        title: String,
        content: String,
        sourceNoteIDs: [UUID],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.content = content
        self.sourceNoteIDs = sourceNoteIDs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
