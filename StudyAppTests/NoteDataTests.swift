import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
struct NoteDataTests {
    private func makeNote(
        documentID: UUID,
        content: String = "Inhalt",
        format: NoteFormat = .plainText,
        updatedAt: Date = Date(timeIntervalSince1970: 100)
    ) -> LectureNote {
        LectureNote(
            id: UUID(), slideDocumentID: documentID, title: "Notizen", content: content,
            format: format, pageNumber: nil,
            createdAt: Date(timeIntervalSince1970: 50), updatedAt: updatedAt
        )
    }

    @Test func roundTripPreservesAllFields() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataNoteRepository(context: container.mainContext)
            let documentID = UUID()
            var note = makeNote(documentID: documentID, content: "$$\\int_0^1 x\\,dx$$", format: .latex)
            note.pageNumber = 7

            try repository.add(note)

            #expect(try repository.notes(forSlideDocument: documentID) == [note])
        }
    }

    @Test func updateChangesMutableFieldsOnly() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataNoteRepository(context: container.mainContext)
            let documentID = UUID()
            let note = makeNote(documentID: documentID)
            try repository.add(note)

            var changed = note
            changed.content = "# Neu"
            changed.format = .markdown
            changed.updatedAt = Date(timeIntervalSince1970: 500)
            try repository.update(changed)

            let stored = try #require(try repository.notes(forSlideDocument: documentID).first)
            #expect(stored.content == "# Neu")
            #expect(stored.format == .markdown)
            #expect(stored.updatedAt == Date(timeIntervalSince1970: 500))
            #expect(stored.createdAt == note.createdAt)
            #expect(stored.id == note.id)
        }
    }

    @Test func notesAreFilteredByDocumentAndSortedNewestFirst() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataNoteRepository(context: container.mainContext)
            let documentA = UUID()
            let documentB = UUID()
            try repository.add(makeNote(documentID: documentA, content: "alt", updatedAt: Date(timeIntervalSince1970: 100)))
            try repository.add(makeNote(documentID: documentA, content: "neu", updatedAt: Date(timeIntervalSince1970: 200)))
            try repository.add(makeNote(documentID: documentB, content: "fremd"))

            let result = try repository.notes(forSlideDocument: documentA)

            #expect(result.map(\.content) == ["neu", "alt"])
        }
    }

    @Test func deleteRemovesNoteAndUnknownIDThrowsNotFound() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataNoteRepository(context: container.mainContext)
            let documentID = UUID()
            let note = makeNote(documentID: documentID)
            try repository.add(note)

            try repository.delete(id: note.id)
            #expect(try repository.notes(forSlideDocument: documentID).isEmpty)

            #expect(throws: NoteError.notFound) {
                try repository.delete(id: note.id)
            }
            #expect(throws: NoteError.notFound) {
                try repository.update(note)
            }
        }
    }

    @Test func deleteNotesForDocumentLeavesOtherDocumentsAlone() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataNoteRepository(context: container.mainContext)
            let documentA = UUID()
            let documentB = UUID()
            try repository.add(makeNote(documentID: documentA))
            try repository.add(makeNote(documentID: documentA))
            try repository.add(makeNote(documentID: documentB))

            try repository.deleteNotes(forSlideDocument: documentA)
            // Deleting again, or for a document without notes, is not an error.
            try repository.deleteNotes(forSlideDocument: documentA)

            #expect(try repository.notes(forSlideDocument: documentA).isEmpty)
            #expect(try repository.notes(forSlideDocument: documentB).count == 1)
        }
    }

    @Test func unknownStoredFormatFallsBackToPlainText() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let context = container.mainContext
            let documentID = UUID()
            context.insert(NoteRecord(
                id: UUID(), slideDocumentID: documentID, title: "Zukunft", content: "x",
                formatRaw: "asciidoc", pageNumber: nil,
                createdAt: Date(), updatedAt: Date()
            ))
            try context.save()

            let repository = SwiftDataNoteRepository(context: context)

            #expect(try repository.notes(forSlideDocument: documentID).first?.format == .plainText)
        }
    }
}
