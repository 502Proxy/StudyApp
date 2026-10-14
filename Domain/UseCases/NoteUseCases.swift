import Foundation

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// Loads the note of a slide document.
@MainActor
struct GetNoteUseCase {
    let repository: any NoteRepository

    /// - Returns: The most recently updated note, or `nil` if the user has not written one yet.
    func callAsFunction(slideDocumentID: UUID, pageNumber: Int? = nil) throws -> LectureNote? {
        try repository.notes(forSlideDocument: slideDocumentID)
            .first { $0.pageNumber == pageNumber }
    }
}

/// Lists document-wide and page-specific notes for search and export.
@MainActor
struct ListNotesUseCase {
    let repository: any NoteRepository

    func callAsFunction(slideDocumentID: UUID) throws -> [LectureNote] {
        try repository.notes(forSlideDocument: slideDocumentID)
    }
}

/// Creates or updates one note for a given scope: either the whole slide document or one PDF page.
/// The scope is identified by the combination of `slideDocumentID` and `pageNumber`.
@MainActor
struct SaveNoteUseCase {
    static let fallbackTitle = "Notizen"

    let repository: any NoteRepository
    /// Clock used for `createdAt` / `updatedAt`. Injectable to keep tests deterministic.
    var now: () -> Date = { Date() }

    /// Saves the given state. If nothing changed, the stored note is returned untouched,
    /// so `updatedAt` only moves on real edits (autosave can call this freely).
    ///
    /// Content is stored verbatim; whitespace is meaningful in Markdown and LaTeX.
    @discardableResult
    func callAsFunction(
        slideDocumentID: UUID,
        title: String,
        content: String,
        format: NoteFormat,
        pageNumber: Int? = nil
    ) throws -> LectureNote {
        let cleanTitle = title.trimmed.isEmpty ? Self.fallbackTitle : title.trimmed

        guard var note = try repository.notes(forSlideDocument: slideDocumentID)
            .first(where: { $0.pageNumber == pageNumber }) else {
            let timestamp = now()
            let created = LectureNote(
                id: UUID(),
                slideDocumentID: slideDocumentID,
                title: cleanTitle,
                content: content,
                format: format,
                pageNumber: pageNumber,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try repository.add(created)
            return created
        }

        guard note.title != cleanTitle
            || note.content != content
            || note.format != format
            || note.pageNumber != pageNumber else {
            return note
        }
        note.title = cleanTitle
        note.content = content
        note.format = format
        note.pageNumber = pageNumber
        note.updatedAt = now()
        try repository.update(note)
        return note
    }
}

/// Deletes notes by note ID or all notes of a slide document.
@MainActor
struct DeleteNoteUseCase {
    let repository: any NoteRepository

    func callAsFunction(id: UUID) throws {
        try repository.delete(id: id)
    }

    func callAsFunction(slideDocumentID: UUID) throws {
        try repository.deleteNotes(forSlideDocument: slideDocumentID)
    }
}
