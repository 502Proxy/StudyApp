import Foundation
import Observation

/// Erzeugt das ViewModel für die Folien eines Moduls. Wird in `AppContainer` verdrahtet.
typealias SlidesViewModelFactory = @MainActor (UUID) -> SlidesViewModel

@MainActor
@Observable
final class SlidesViewModel {
    let moduleID: UUID
    private(set) var documents: [SlideDocument] = []
    var openDocumentID: UUID?
    /// Seite (1-basiert), auf die der Reader beim Öffnen springt.
    private(set) var requestedPage: Int?
    /// Ändert sich bei jedem Öffnen, damit ein bereits offener Reader erneut springt.
    private(set) var pageRequestID = UUID()
    var isImporterPresented = false
    var errorMessage: String?

    private let listDocuments: ListSlideDocumentsUseCase
    private let importDocument: ImportSlideDocumentUseCase
    private let renameDocument: RenameSlideDocumentUseCase
    private let deleteDocument: DeleteSlideDocumentUseCase
    private let storage: any FileStorage
    private let notesViewModelFactory: NotesViewModelFactory
    private let readingProgress: any ReadingProgressStore

    init(
        moduleID: UUID,
        repository: any SlideDocumentRepository,
        noteRepository: any NoteRepository,
        storage: any FileStorage,
        inspector: any PDFInspector,
        readingProgress: any ReadingProgressStore,
        notesViewModelFactory: @escaping NotesViewModelFactory
    ) {
        self.moduleID = moduleID
        self.storage = storage
        self.readingProgress = readingProgress
        self.notesViewModelFactory = notesViewModelFactory
        listDocuments = ListSlideDocumentsUseCase(repository: repository)
        importDocument = ImportSlideDocumentUseCase(
            repository: repository, storage: storage, inspector: inspector
        )
        renameDocument = RenameSlideDocumentUseCase(repository: repository)
        deleteDocument = DeleteSlideDocumentUseCase(
            repository: repository, noteRepository: noteRepository, storage: storage
        )
    }

    var openDocument: SlideDocument? {
        documents.first { $0.id == openDocumentID }
    }

    func load() {
        do {
            documents = try listDocuments(moduleID: moduleID)
            if let openDocumentID, !documents.contains(where: { $0.id == openDocumentID }) {
                self.openDocumentID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Öffnet einen Foliensatz – auf `page` oder dort, wo zuletzt gelesen wurde.
    func open(_ document: SlideDocument, page: Int? = nil) {
        requestedPage = page ?? readingProgress.lastPage(for: document.id)
        pageRequestID = UUID()
        openDocumentID = document.id
        readingProgress.setLastOpenedDocument(document.id, inModule: moduleID)
    }

    func open(documentID: UUID, page: Int? = nil) {
        if documents.isEmpty { load() }
        guard let document = documents.first(where: { $0.id == documentID }) else { return }
        open(document, page: page)
    }

    /// Zuletzt gelesener Foliensatz, sonst der zuletzt importierte.
    var documentToResume: SlideDocument? {
        if let id = readingProgress.lastOpenedDocument(inModule: moduleID),
           let document = documents.first(where: { $0.id == id }) {
            return document
        }
        return documents.max { $0.importedAt < $1.importedAt }
    }

    /// Öffnet `documentToResume`. Gibt `false` zurück, wenn es keine Folien gibt.
    @discardableResult
    func resumeReading() -> Bool {
        load()
        guard let document = documentToResume else { return false }
        open(document)
        return true
    }

    func lastPage(for document: SlideDocument) -> Int? {
        readingProgress.lastPage(for: document.id)
    }

    /// Merkt sich die aktuelle Seite für „Weiterlesen“.
    func recordPage(_ page: Int, for document: SlideDocument) {
        guard page >= 1 else { return }
        readingProgress.setLastPage(page, for: document.id)
    }

    /// Speichert ein PDF mit geänderten Markierungen in den App-Speicher.
    func saveAnnotatedDocument(_ data: Data, for document: SlideDocument) throws {
        try storage.write(data, as: document.fileName)
    }

    func close() {
        openDocumentID = nil
        requestedPage = nil
    }

    func fileURL(for document: SlideDocument) -> URL {
        storage.url(for: document.fileName)
    }

    /// Creates the notes view model for a document. The reader calls this once per opened document.
    func makeNotesViewModel(for document: SlideDocument) -> NotesViewModel {
        notesViewModelFactory(document)
    }

    /// Importiert mehrere PDFs. Fehlerhafte Dateien werden übersprungen und gesammelt gemeldet.
    func importPDFs(_ urls: [URL]) {
        var failures: [String] = []
        var imported: [SlideDocument] = []
        for url in urls {
            do {
                imported.append(try importDocument(from: url, moduleID: moduleID))
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        load()
        // Ein einzelner neuer Foliensatz wird direkt geöffnet – typisch kurz vor der Vorlesung.
        if imported.count == 1, failures.isEmpty, let document = imported.first {
            open(document)
        }
        if !failures.isEmpty {
            errorMessage = failures.joined(separator: "\n")
        }
    }

    func rename(_ document: SlideDocument, to title: String) {
        do {
            try renameDocument(document, to: title)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ document: SlideDocument) {
        do {
            try deleteDocument(document)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
