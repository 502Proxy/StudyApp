import Foundation
import Testing
@testable import StudyApp

@MainActor
struct NotesViewModelTests {
    private let document = SlideDocument(
        id: UUID(), moduleID: UUID(), title: "Vorlesung 1",
        fileName: "a.pdf", pageCount: 10, importedAt: Date()
    )
    private let repository = FakeNoteRepository()

    private func makeViewModel(delay: Duration = .milliseconds(10)) -> NotesViewModel {
        NotesViewModel(document: document, repository: repository, autosaveDelay: delay)
    }

    /// Polls until `condition` holds, so the tests do not depend on exact timer precision.
    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<150 where !condition() {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func loadWithoutNoteStartsEmptyAndClean() {
        let viewModel = makeViewModel()

        viewModel.load()

        #expect(viewModel.content.isEmpty)
        #expect(viewModel.format == .plainText)
        #expect(!viewModel.hasUnsavedChanges)
        #expect(viewModel.saveState == .saved)
    }

    @Test func loadRestoresStoredNote() {
        repository.storage = [LectureNote(
            id: UUID(), slideDocumentID: document.id, title: "Vorlesung 1", content: "# Hi",
            format: .markdown, pageNumber: nil, createdAt: Date(), updatedAt: Date()
        )]
        let viewModel = makeViewModel()

        viewModel.load()

        #expect(viewModel.content == "# Hi")
        #expect(viewModel.format == .markdown)
        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test func saveNowPersistsEditsWithDocumentTitle() {
        let viewModel = makeViewModel(delay: .seconds(60))
        viewModel.load()

        viewModel.content = "Notiz"
        viewModel.format = .latex
        viewModel.noteDidChange()
        #expect(viewModel.saveState == .pending)
        viewModel.saveNow()

        #expect(viewModel.saveState == .saved)
        #expect(repository.storage.count == 1)
        #expect(repository.storage.first?.content == "Notiz")
        #expect(repository.storage.first?.format == .latex)
        #expect(repository.storage.first?.title == "Vorlesung 1")
    }

    @Test func saveNowWithoutEditsDoesNotCreateNote() {
        let viewModel = makeViewModel()
        viewModel.load()

        viewModel.saveNow()

        #expect(repository.storage.isEmpty)
    }

    @Test func editsAreSavedAutomaticallyAfterDelay() async throws {
        let viewModel = makeViewModel()
        viewModel.load()

        viewModel.content = "Hallo"
        viewModel.noteDidChange()
        try await wait { viewModel.saveState == .saved }

        #expect(repository.storage.first?.content == "Hallo")
    }

    @Test func burstOfEditsIsSavedOnce() async throws {
        let viewModel = makeViewModel(delay: .milliseconds(150))
        viewModel.load()

        for text in ["a", "ab", "abc"] {
            viewModel.content = text
            viewModel.noteDidChange()
        }
        try await wait { viewModel.saveState == .saved }

        #expect(repository.addCount == 1)
        #expect(repository.updateCount == 0)
        #expect(repository.storage.first?.content == "abc")
    }

    @Test func revertingEditsBeforeSaveCancelsPendingSave() async throws {
        let viewModel = makeViewModel(delay: .milliseconds(50))
        viewModel.load()

        viewModel.content = "x"
        viewModel.noteDidChange()
        viewModel.content = ""
        viewModel.noteDidChange()
        try await Task.sleep(for: .milliseconds(200))

        #expect(viewModel.saveState == .saved)
        #expect(repository.storage.isEmpty)
    }
    @Test func pageScopeLoadsAndSavesIndependentNotes() {
        let viewModel = makeViewModel()
        viewModel.load()
        viewModel.content = "Dokumentweite Notiz"
        viewModel.noteDidChange()
        viewModel.saveNow()

        viewModel.selectPageNumber(3)
        #expect(viewModel.pageNumber == 3)
        #expect(viewModel.content.isEmpty)
        viewModel.content = "Ein wichtiger Satz auf Seite drei"
        viewModel.format = .markdown
        viewModel.noteDidChange()
        viewModel.saveNow()

        viewModel.selectPageNumber(nil)
        #expect(viewModel.pageNumber == nil)
        #expect(viewModel.content == "Dokumentweite Notiz")
        viewModel.selectPageNumber(3)
        #expect(viewModel.content == "Ein wichtiger Satz auf Seite drei")
        #expect(viewModel.format == .markdown)
    }

    @Test func searchAndExportIncludeUnsavedCurrentPageNote() {
        let viewModel = makeViewModel()
        viewModel.load()
        viewModel.selectPageNumber(6)
        viewModel.content = "Dieser Entwurf enthält den Begriff Fouriertransformation."
        viewModel.format = .markdown

        viewModel.searchQuery = "fouriertransformation"
        #expect(viewModel.searchResults.count == 1)
        #expect(viewModel.searchResults.first?.pageNumber == 6)
        #expect(viewModel.searchResults.first?.content.contains("Fouriertransformation") == true)

        let export = viewModel.exportAllNotesAsMarkdown()
        #expect(export.contains("Seite 6"))
        #expect(export.contains("Fouriertransformation"))
    }

    @Test func searchAndMarkdownExportIncludePerPageNotes() {
        let viewModel = makeViewModel()
        viewModel.load()
        viewModel.content = "Grenzwertsatz und Konvergenz"
        viewModel.noteDidChange()
        viewModel.saveNow()
        viewModel.selectPageNumber(4)
        viewModel.content = "Eigenwerte und Eigenvektoren"
        viewModel.noteDidChange()
        viewModel.saveNow()

        viewModel.searchQuery = "eigenvektoren"
        #expect(viewModel.searchResults.count == 1)
        #expect(viewModel.searchResults.first?.pageNumber == 4)

        let export = viewModel.exportAllNotesAsMarkdown()
        #expect(export.contains("Gesamtdokument"))
        #expect(export.contains("Seite 4"))
        #expect(export.contains("Grenzwertsatz und Konvergenz"))
        #expect(export.contains("Eigenwerte und Eigenvektoren"))
    }

}
