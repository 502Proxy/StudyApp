import Foundation
import Testing
@testable import StudyApp

@MainActor
struct UserDefaultsStudyPreferencesTests {
    private func makeStore() throws -> UserDefaultsStudyPreferences {
        let suite = "UserDefaultsStudyPreferencesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return UserDefaultsStudyPreferences(defaults: defaults)
    }

    @Test func defaultsAreOnAndLeadTimeIsTenMinutes() throws {
        let store = try makeStore()
        #expect(store.autoCreateModules)
        #expect(store.autoOpenLecture)
        #expect(store.autoRefreshCalendars)
        #expect(store.lectureLeadTime == 600)
        #expect(store.ignoredCourseKeys.isEmpty)
    }

    @Test func valuesRoundTrip() throws {
        let store = try makeStore()
        let document = UUID()
        let module = UUID()
        store.autoOpenLecture = false
        store.lectureLeadMinutes = 0
        store.ignoredCourseKeys = ["physik", "analysis i"]
        store.setLastPage(12, for: document)
        store.setLastOpenedDocument(document, inModule: module)

        #expect(!store.autoOpenLecture)
        #expect(store.lectureLeadTime == 0)
        #expect(store.ignoredCourseKeys == ["physik", "analysis i"])
        #expect(store.lastPage(for: document) == 12)
        #expect(store.lastPage(for: UUID()) == nil)
        #expect(store.lastOpenedDocument(inModule: module) == document)
    }
}

@MainActor
struct NoteQuoteTests {
    private let document = SlideDocument(
        id: UUID(), moduleID: UUID(), title: "VL 3", fileName: "x.pdf", pageCount: 10, importedAt: Date()
    )

    @Test func selectionIsAppendedAsQuoteWithPage() {
        let viewModel = NotesViewModel(document: document, repository: FakeNoteRepository(), autosaveDelay: .seconds(60))
        viewModel.load()
        viewModel.content = "Eigene Gedanken"

        viewModel.appendQuote("Satz von Rolle\n  gilt für stetige f ", fromPage: 4)

        #expect(viewModel.content == "Eigene Gedanken\n\n> Satz von Rolle\n> gilt für stetige f\n> — Folie 4\n\n")
        #expect(viewModel.saveState == .pending)
    }

    @Test func emptySelectionChangesNothing() {
        let viewModel = NotesViewModel(document: document, repository: FakeNoteRepository())
        viewModel.load()
        viewModel.appendQuote(" \n ", fromPage: 1)
        #expect(viewModel.content.isEmpty)
    }

    @Test func previewLineSkipsMarkdownAndTitle() {
        let note = LectureNote(
            id: UUID(), slideDocumentID: UUID(), title: "Vorlesung",
            content: "# Vorlesung\n\n- **Rolle** gilt", format: .markdown,
            pageNumber: nil, createdAt: Date(), updatedAt: Date()
        )
        #expect(note.previewLine() == "**Rolle** gilt")
        #expect(note.hasContent)
    }
}

@MainActor
struct SlideSavingTests {
    @Test func annotatedPDFIsWrittenThroughTheStorage() throws {
        let storage = FakeFileStorage()
        let viewModel = SlidesViewModel(
            moduleID: UUID(),
            repository: FakeSlideDocumentRepository(),
            noteRepository: FakeNoteRepository(),
            storage: storage,
            inspector: FakeInspector(pages: 1),
            readingProgress: InMemoryStudyPreferences(),
            notesViewModelFactory: { NotesViewModel(document: $0, repository: FakeNoteRepository()) }
        )
        let document = SlideDocument(id: UUID(), moduleID: UUID(), title: "VL", fileName: "a.pdf", pageCount: 1, importedAt: Date())

        try viewModel.saveAnnotatedDocument(Data([1, 2, 3]), for: document)

        #expect(storage.written["a.pdf"] == Data([1, 2, 3]))
    }
}

@MainActor
struct NoteExportTests {
    private func note(_ content: String, page: Int? = nil, format: NoteFormat = .markdown, title: String = "Notiz") -> LectureNote {
        LectureNote(
            id: UUID(), slideDocumentID: UUID(), title: title, content: content, format: format,
            pageNumber: page, createdAt: Date(), updatedAt: Date()
        )
    }

    @Test func fileNamesContainScopeAndMatchingExtension() {
        #expect(NoteExportFormatting.fileName(for: note("x", page: 4), documentTitle: "VL 3: Analysis") == "VL 3- Analysis_Seite_4.md")
        #expect(NoteExportFormatting.fileName(for: note("x", format: .latex), documentTitle: "VL") == "VL_Gesamtdokument.tex")
        #expect(NoteExportFormatting.fileName(for: note("x", format: .plainText, title: "Vorlesung 1/2"), documentTitle: nil) == "Vorlesung 1-2.txt")
        #expect(NoteExportFormatting.safeFileName("  ") == "Notizen")
    }

    @Test func markdownSkipsEmptyNotes() {
        let text = NoteExportFormatting.markdown(title: "Notizen: Analysis", sections: [
            ("Seite 1", note("Grenzwert")),
            ("Seite 2", note("   ")),
        ])
        #expect(text.hasPrefix("# Notizen: Analysis"))
        #expect(text.contains("## Seite 1"))
        #expect(!text.contains("## Seite 2"))
    }

    @Test func moduleExportContainsFreeAndSlideNotes() throws {
        let module = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: Date())
        let slides = FakeSlideDocumentRepository()
        let document = SlideDocument(id: UUID(), moduleID: module.id, title: "VL 1", fileName: "a.pdf", pageCount: 5, importedAt: Date())
        try slides.add(document)
        let notes = FakeNoteRepository()
        try notes.add(LectureNote(
            id: UUID(), slideDocumentID: document.id, title: "VL 1", content: "Folieninhalt", format: .markdown,
            pageNumber: 2, createdAt: Date(), updatedAt: Date()
        ))
        let viewModel = LearningViewModel(
            module: module, slideRepository: slides, noteRepository: notes,
            flashcardRepository: FakeFlashcardRepository(), studySheetRepository: FakeStudySheetRepository()
        )
        viewModel.load()
        let free = try #require(viewModel.addModuleNote(title: "Vorlesung vom 20.10.2026", content: "Eigene Notiz"))

        let export = viewModel.exportAllNotesAsMarkdown()
        #expect(export.contains("## Vorlesung vom 20.10.2026"))
        #expect(export.contains("## VL 1 – Seite 2"))
        #expect(viewModel.exportContent(forNoteWithID: free.id)?.fileName == "Vorlesung vom 20.10.2026.md")
    }
}
