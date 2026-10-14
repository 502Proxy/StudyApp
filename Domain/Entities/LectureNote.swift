import Foundation

/// A note the user took while studying a `SlideDocument`.
///
/// The link to the slides is a plain ID (like `SlideDocument.moduleID`); cleaning up
/// notes when their slides are deleted is the job of the delete use cases.
struct LectureNote: Identifiable, Hashable, Sendable {
    let id: UUID
    let slideDocumentID: UUID
    var title: String
    var content: String
    var format: NoteFormat
    /// 1-based page the note refers to. `nil` means the note covers the whole document.
    var pageNumber: Int?
    let createdAt: Date
    var updatedAt: Date
}
