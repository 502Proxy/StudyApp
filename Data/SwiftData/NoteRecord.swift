import Foundation
import SwiftData

/// SwiftData model for lecture notes. The link to the slides is a plain ID, so
/// deleting a slide document is handled by the use case, not by a relationship.
@Model
final class NoteRecord {
    @Attribute(.unique) var id: UUID
    var slideDocumentID: UUID
    var title: String
    var content: String
    /// Raw value of `NoteFormat`. Stored as `String` so unknown future values cannot break loading.
    var formatRaw: String
    var pageNumber: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        slideDocumentID: UUID,
        title: String,
        content: String,
        formatRaw: String,
        pageNumber: Int?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.slideDocumentID = slideDocumentID
        self.title = title
        self.content = content
        self.formatRaw = formatRaw
        self.pageNumber = pageNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension NoteRecord {
    convenience init(_ note: LectureNote) {
        self.init(
            id: note.id,
            slideDocumentID: note.slideDocumentID,
            title: note.title,
            content: note.content,
            formatRaw: note.format.rawValue,
            pageNumber: note.pageNumber,
            createdAt: note.createdAt,
            updatedAt: note.updatedAt
        )
    }

    func toDomain() -> LectureNote {
        LectureNote(
            id: id,
            slideDocumentID: slideDocumentID,
            title: title,
            content: content,
            format: NoteFormat(rawValue: formatRaw) ?? .plainText,
            pageNumber: pageNumber,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// Copies the mutable fields. `id`, `slideDocumentID` and `createdAt` never change.
    func apply(_ note: LectureNote) {
        title = note.title
        content = note.content
        formatRaw = note.format.rawValue
        pageNumber = note.pageNumber
        updatedAt = note.updatedAt
    }
}
