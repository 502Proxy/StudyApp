import Foundation
import Testing
@testable import StudyApp

// MARK: Testdoubles

@MainActor
final class FakeSlideDocumentRepository: SlideDocumentRepository {
    var storage: [SlideDocument] = []

    func documents(forModule moduleID: UUID) throws -> [SlideDocument] {
        storage.filter { $0.moduleID == moduleID }
    }

    func add(_ document: SlideDocument) throws {
        storage.append(document)
    }

    func update(_ document: SlideDocument) throws {
        guard let index = storage.firstIndex(where: { $0.id == document.id }) else {
            throw SlideError.notFound
        }
        storage[index] = document
    }

    func delete(id: UUID) throws {
        guard storage.contains(where: { $0.id == id }) else { throw SlideError.notFound }
        storage.removeAll { $0.id == id }
    }
}

/// Nur in Tests und nur vom Main Actor benutzt, daher `@unchecked Sendable`.
final class FakeFileStorage: FileStorage, @unchecked Sendable {
    private(set) var files: Set<String> = []

    func store(copyOf sourceURL: URL, as fileName: String) throws {
        files.insert(fileName)
    }

    func url(for fileName: String) -> URL {
        URL(fileURLWithPath: "/fake/\(fileName)")
    }

    func remove(fileName: String) throws {
        files.remove(fileName)
    }
}

struct FakeInspector: PDFInspector {
    var pages: Int?

    func pageCount(at url: URL) -> Int? { pages }
}

// MARK: Tests

@MainActor
struct SlideUseCaseTests {
    private let moduleID = UUID()

    private func makeDocument(title: String, moduleID: UUID) -> SlideDocument {
        let id = UUID()
        return SlideDocument(
            id: id, moduleID: moduleID, title: title,
            fileName: "\(id.uuidString).pdf", pageCount: 10, importedAt: Date()
        )
    }

    @Test func importStoresFileAndRecord() throws {
        let repository = FakeSlideDocumentRepository()
        let storage = FakeFileStorage()
        let importPDF = ImportSlideDocumentUseCase(
            repository: repository, storage: storage, inspector: FakeInspector(pages: 42)
        )

        let document = try importPDF(
            from: URL(fileURLWithPath: "/tmp/Vorlesung 1.pdf"), moduleID: moduleID
        )

        #expect(document.title == "Vorlesung 1")
        #expect(document.pageCount == 42)
        #expect(document.moduleID == moduleID)
        #expect(storage.files == [document.fileName])
        #expect(repository.storage.count == 1)
    }

    @Test func importOfInvalidPDFRemovesCopiedFile() {
        let repository = FakeSlideDocumentRepository()
        let storage = FakeFileStorage()
        let importPDF = ImportSlideDocumentUseCase(
            repository: repository, storage: storage, inspector: FakeInspector(pages: nil)
        )

        #expect(throws: SlideError.invalidPDF("kaputt.pdf")) {
            try importPDF(from: URL(fileURLWithPath: "/tmp/kaputt.pdf"), moduleID: moduleID)
        }
        #expect(storage.files.isEmpty)
        #expect(repository.storage.isEmpty)
    }

    @Test func renameTrimsAndRejectsEmptyTitle() throws {
        let repository = FakeSlideDocumentRepository()
        let document = makeDocument(title: "Alt", moduleID: moduleID)
        repository.storage = [document]
        let rename = RenameSlideDocumentUseCase(repository: repository)

        let renamed = try rename(document, to: "  Neu  ")
        #expect(renamed.title == "Neu")
        #expect(repository.storage.first?.title == "Neu")

        #expect(throws: SlideError.emptyTitle) {
            try rename(document, to: "   ")
        }
    }

    @Test func deleteRemovesRecordAndFile() throws {
        let repository = FakeSlideDocumentRepository()
        let storage = FakeFileStorage()
        let importPDF = ImportSlideDocumentUseCase(
            repository: repository, storage: storage, inspector: FakeInspector(pages: 3)
        )
        let document = try importPDF(from: URL(fileURLWithPath: "/tmp/a.pdf"), moduleID: moduleID)

        try DeleteSlideDocumentUseCase(
            repository: repository, noteRepository: FakeNoteRepository(), storage: storage
        )(document)

        #expect(repository.storage.isEmpty)
        #expect(storage.files.isEmpty)
    }

    @Test func listSortsNaturally() throws {
        let repository = FakeSlideDocumentRepository()
        repository.storage = [
            makeDocument(title: "Folie 10", moduleID: moduleID),
            makeDocument(title: "Folie 2", moduleID: moduleID),
            makeDocument(title: "Fremd", moduleID: UUID()),
        ]

        let result = try ListSlideDocumentsUseCase(repository: repository)(moduleID: moduleID)

        #expect(result.map(\.title) == ["Folie 2", "Folie 10"])
    }

    @Test func deletingModuleAlsoDeletesItsSlides() throws {
        let moduleRepository = FakeModuleRepository()
        let slideRepository = FakeSlideDocumentRepository()
        let storage = FakeFileStorage()
        let module = try CreateModuleUseCase(repository: moduleRepository)(
            name: "Analysis", code: "", color: .blue
        )
        let importPDF = ImportSlideDocumentUseCase(
            repository: slideRepository, storage: storage, inspector: FakeInspector(pages: 5)
        )
        try importPDF(from: URL(fileURLWithPath: "/tmp/a.pdf"), moduleID: module.id)
        try importPDF(from: URL(fileURLWithPath: "/tmp/b.pdf"), moduleID: module.id)
        try importPDF(from: URL(fileURLWithPath: "/tmp/c.pdf"), moduleID: UUID())

        try DeleteModuleUseCase(
            repository: moduleRepository,
            slideRepository: slideRepository,
            noteRepository: FakeNoteRepository(),
            flashcardRepository: FakeFlashcardRepository(),
            studySheetRepository: FakeStudySheetRepository(),
            fileStorage: storage
        )(module)

        #expect(moduleRepository.storage.isEmpty)
        #expect(slideRepository.storage.count == 1)
        #expect(storage.files.count == 1)
    }
}
