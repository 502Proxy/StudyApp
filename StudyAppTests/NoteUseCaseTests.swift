import Foundation
import Testing
@testable import StudyApp

// MARK: Test doubles

@MainActor
final class FakeNoteRepository: NoteRepository {
    var storage: [LectureNote] = []
    private(set) var addCount = 0
    private(set) var updateCount = 0

    func notes(forSlideDocument slideDocumentID: UUID) throws -> [LectureNote] {
        storage
            .filter { $0.slideDocumentID == slideDocumentID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func add(_ note: LectureNote) throws {
        addCount += 1
        storage.append(note)
    }

    func update(_ note: LectureNote) throws {
        guard let index = storage.firstIndex(where: { $0.id == note.id }) else {
            throw NoteError.notFound
        }
        updateCount += 1
        storage[index] = note
    }

    func delete(id: UUID) throws {
        guard storage.contains(where: { $0.id == id }) else { throw NoteError.notFound }
        storage.removeAll { $0.id == id }
    }

    func deleteNotes(forSlideDocument slideDocumentID: UUID) throws {
        storage.removeAll { $0.slideDocumentID == slideDocumentID }
    }
}

/// Manually advanced clock, so timestamps in tests are exact.
@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000)

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

// MARK: Tests

@MainActor
struct NoteUseCaseTests {
    private let documentID = UUID()
    private let clock = TestClock()
    private let repository = FakeNoteRepository()

    private func makeSave() -> SaveNoteUseCase {
        SaveNoteUseCase(repository: repository, now: { [clock] in clock.now })
    }

    private func makeNote(content: String, updatedAt: Date, documentID: UUID) -> LectureNote {
        LectureNote(
            id: UUID(), slideDocumentID: documentID, title: "Notizen", content: content,
            format: .plainText, pageNumber: nil, createdAt: updatedAt, updatedAt: updatedAt
        )
    }

    // MARK: Save

    @Test func firstSaveCreatesNoteWithTimestamps() throws {
        let note = try makeSave()(
            slideDocumentID: documentID, title: "Analysis 1", content: "Hallo", format: .markdown
        )

        #expect(note.slideDocumentID == documentID)
        #expect(note.title == "Analysis 1")
        #expect(note.content == "Hallo")
        #expect(note.format == .markdown)
        #expect(note.pageNumber == nil)
        #expect(note.createdAt == clock.now)
        #expect(note.updatedAt == clock.now)
        #expect(repository.storage == [note])
    }

    @Test func secondSaveUpdatesTheSameNote() throws {
        let save = makeSave()
        let created = try save(slideDocumentID: documentID, title: "T", content: "eins", format: .plainText)
        clock.advance(by: 60)

        let updated = try save(slideDocumentID: documentID, title: "T", content: "zwei", format: .plainText)

        #expect(updated.id == created.id)
        #expect(updated.createdAt == created.createdAt)
        #expect(updated.updatedAt == clock.now)
        #expect(updated.content == "zwei")
        #expect(repository.storage.count == 1)
    }

    @Test func saveWithoutChangesKeepsTimestamp() throws {
        let save = makeSave()
        let created = try save(slideDocumentID: documentID, title: "T", content: "x", format: .latex)
        clock.advance(by: 60)

        let again = try save(slideDocumentID: documentID, title: "T", content: "x", format: .latex)

        #expect(again == created)
        #expect(repository.updateCount == 0)
    }

    @Test func switchingFormatIsPersistedAndKeepsContent() throws {
        let save = makeSave()
        try save(slideDocumentID: documentID, title: "T", content: "$x^2$", format: .plainText)
        clock.advance(by: 5)

        let switched = try save(slideDocumentID: documentID, title: "T", content: "$x^2$", format: .latex)

        #expect(switched.format == .latex)
        #expect(switched.content == "$x^2$")
        #expect(switched.updatedAt == clock.now)
        #expect(repository.storage.first?.format == .latex)
    }

    @Test func saveKeepsWhitespaceOfContentButTrimsTitle() throws {
        let note = try makeSave()(
            slideDocumentID: documentID, title: "  Titel  ", content: "  eingerückt\n", format: .markdown
        )

        #expect(note.title == "Titel")
        #expect(note.content == "  eingerückt\n")
    }

    @Test func blankTitleFallsBackToDefault() throws {
        let note = try makeSave()(
            slideDocumentID: documentID, title: "   ", content: "x", format: .plainText
        )

        #expect(note.title == SaveNoteUseCase.fallbackTitle)
    }

    @Test func notesOfDifferentDocumentsAreIndependent() throws {
        let save = makeSave()
        let other = UUID()

        try save(slideDocumentID: documentID, title: "A", content: "a", format: .plainText)
        try save(slideDocumentID: other, title: "B", content: "b", format: .plainText)

        #expect(repository.storage.count == 2)
    }

    // MARK: Get

    @Test func getReturnsNilWithoutNote() throws {
        let result = try GetNoteUseCase(repository: repository)(slideDocumentID: documentID)

        #expect(result == nil)
    }

    @Test func getReturnsMostRecentlyUpdatedNote() throws {
        let older = makeNote(content: "alt", updatedAt: Date(timeIntervalSince1970: 100), documentID: documentID)
        let newer = makeNote(content: "neu", updatedAt: Date(timeIntervalSince1970: 200), documentID: documentID)
        repository.storage = [older, newer]

        let result = try GetNoteUseCase(repository: repository)(slideDocumentID: documentID)

        #expect(result?.content == "neu")
    }

    // MARK: Delete

    @Test func deleteByIDRemovesOnlyThatNote() throws {
        let keep = makeNote(content: "keep", updatedAt: clock.now, documentID: documentID)
        let remove = makeNote(content: "remove", updatedAt: clock.now, documentID: documentID)
        repository.storage = [keep, remove]

        try DeleteNoteUseCase(repository: repository)(id: remove.id)

        #expect(repository.storage == [keep])
    }

    @Test func deleteByUnknownIDThrowsNotFound() {
        #expect(throws: NoteError.notFound) {
            try DeleteNoteUseCase(repository: repository)(id: UUID())
        }
    }

    @Test func deleteByDocumentRemovesAllItsNotes() throws {
        let other = makeNote(content: "x", updatedAt: clock.now, documentID: UUID())
        repository.storage = [
            makeNote(content: "a", updatedAt: clock.now, documentID: documentID),
            makeNote(content: "b", updatedAt: clock.now, documentID: documentID),
            other,
        ]

        try DeleteNoteUseCase(repository: repository)(slideDocumentID: documentID)

        #expect(repository.storage == [other])
    }

    // MARK: Cascade

    @Test func deletingSlideDocumentAlsoDeletesItsNotes() throws {
        let slideRepository = FakeSlideDocumentRepository()
        let storage = FakeFileStorage()
        let document = try ImportSlideDocumentUseCase(
            repository: slideRepository, storage: storage, inspector: FakeInspector(pages: 3)
        )(from: URL(fileURLWithPath: "/tmp/a.pdf"), moduleID: UUID())
        let foreign = makeNote(content: "fremd", updatedAt: clock.now, documentID: UUID())
        repository.storage = [
            makeNote(content: "meins", updatedAt: clock.now, documentID: document.id),
            foreign,
        ]

        try DeleteSlideDocumentUseCase(
            repository: slideRepository, noteRepository: repository, storage: storage
        )(document)

        #expect(repository.storage == [foreign])
        #expect(slideRepository.storage.isEmpty)
        #expect(storage.files.isEmpty)
    }

    @Test func deletingModuleAlsoDeletesNotesOfItsSlides() throws {
        let moduleRepository = FakeModuleRepository()
        let slideRepository = FakeSlideDocumentRepository()
        let storage = FakeFileStorage()
        let module = try CreateModuleUseCase(repository: moduleRepository)(
            name: "Analysis", code: "", color: .blue
        )
        let importPDF = ImportSlideDocumentUseCase(
            repository: slideRepository, storage: storage, inspector: FakeInspector(pages: 5)
        )
        let first = try importPDF(from: URL(fileURLWithPath: "/tmp/a.pdf"), moduleID: module.id)
        let second = try importPDF(from: URL(fileURLWithPath: "/tmp/b.pdf"), moduleID: module.id)
        let foreignDocument = try importPDF(from: URL(fileURLWithPath: "/tmp/c.pdf"), moduleID: UUID())
        let foreignNote = makeNote(content: "bleibt", updatedAt: clock.now, documentID: foreignDocument.id)
        repository.storage = [
            makeNote(content: "1", updatedAt: clock.now, documentID: first.id),
            makeNote(content: "2", updatedAt: clock.now, documentID: second.id),
            foreignNote,
        ]

        try DeleteModuleUseCase(
            repository: moduleRepository,
            slideRepository: slideRepository,
            noteRepository: repository,
            flashcardRepository: FakeFlashcardRepository(),
            studySheetRepository: FakeStudySheetRepository(),
            fileStorage: storage
        )(module)

        #expect(repository.storage == [foreignNote])
    }
    @Test func pageNotesAndDocumentNoteAreSavedIndependently() throws {
        let save = makeSave()
        let documentNote = try save(
            slideDocumentID: documentID, title: "T", content: "Allgemein", format: .markdown
        )
        let pageTwo = try save(
            slideDocumentID: documentID, title: "T", content: "Seite zwei", format: .markdown, pageNumber: 2
        )
        let pageFive = try save(
            slideDocumentID: documentID, title: "T", content: "Seite fünf", format: .plainText, pageNumber: 5
        )

        clock.advance(by: 10)
        let updatedPageTwo = try save(
            slideDocumentID: documentID, title: "T", content: "Seite zwei aktualisiert",
            format: .markdown, pageNumber: 2
        )

        #expect(repository.storage.count == 3)
        #expect(updatedPageTwo.id == pageTwo.id)
        #expect(updatedPageTwo.pageNumber == 2)
        #expect(try GetNoteUseCase(repository: repository)(slideDocumentID: documentID)?.id == documentNote.id)
        #expect(try GetNoteUseCase(repository: repository)(slideDocumentID: documentID, pageNumber: 2)?.content == "Seite zwei aktualisiert")
        #expect(try GetNoteUseCase(repository: repository)(slideDocumentID: documentID, pageNumber: 5)?.id == pageFive.id)
    }

}
