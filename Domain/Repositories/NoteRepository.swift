import Foundation

enum NoteError: Error, Equatable, LocalizedError {
    case notFound

    var errorDescription: String? {
        switch self {
        case .notFound: "Die Notiz wurde nicht gefunden."
        }
    }
}

/// Access to stored lecture notes. The implementation lives in the data layer.
/// `@MainActor` because the SwiftData implementation uses the main context.
@MainActor
protocol NoteRepository {
    /// All notes of a slide document, most recently updated first.
    func notes(forSlideDocument slideDocumentID: UUID) throws -> [LectureNote]
    func add(_ note: LectureNote) throws
    /// - Throws: `NoteError.notFound` if no note with this ID exists.
    func update(_ note: LectureNote) throws
    /// - Throws: `NoteError.notFound` if no note with this ID exists.
    func delete(id: UUID) throws
    /// Removes every note of a slide document. Having no notes is not an error.
    func deleteNotes(forSlideDocument slideDocumentID: UUID) throws
}
