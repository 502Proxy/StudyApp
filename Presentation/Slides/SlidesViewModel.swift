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
    var isImporterPresented = false
    var errorMessage: String?

    private let listDocuments: ListSlideDocumentsUseCase
    private let importDocument: ImportSlideDocumentUseCase
    private let renameDocument: RenameSlideDocumentUseCase
    private let deleteDocument: DeleteSlideDocumentUseCase
    private let storage: any FileStorage
    private let notesViewModelFactory: NotesViewModelFactory

    init(
        moduleID: UUID,
        repository: any SlideDocumentRepository,
        noteRepository: any NoteRepository,
        storage: any FileStorage,
        inspector: any PDFInspector,
        notesViewModelFactory: @escaping NotesViewModelFactory
    ) {
        self.moduleID = moduleID
        self.storage = storage
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

    func open(_ document: SlideDocument) {
        openDocumentID = document.id
    }

    func close() {
        openDocumentID = nil
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
        for url in urls {
            do {
                try importDocument(from: url, moduleID: moduleID)
            } catch {
                failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        load()
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
