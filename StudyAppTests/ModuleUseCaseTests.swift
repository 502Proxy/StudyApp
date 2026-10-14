import Foundation
import Testing
@testable import StudyApp

@MainActor
final class FakeModuleRepository: ModuleRepository {
    var storage: [StudyModule] = []

    func all() throws -> [StudyModule] { storage }

    func add(_ module: StudyModule) throws {
        storage.append(module)
    }

    func update(_ module: StudyModule) throws {
        guard let index = storage.firstIndex(where: { $0.id == module.id }) else {
            throw ModuleError.notFound
        }
        storage[index] = module
    }

    func delete(id: UUID) throws {
        guard storage.contains(where: { $0.id == id }) else { throw ModuleError.notFound }
        storage.removeAll { $0.id == id }
    }
}

@MainActor
struct ModuleUseCaseTests {
    @Test func createTrimsInputAndStores() throws {
        let repository = FakeModuleRepository()
        let create = CreateModuleUseCase(repository: repository)

        let module = try create(name: "  Analysis I  ", code: " MAT101 ", color: .blue)

        #expect(module.name == "Analysis I")
        #expect(module.code == "MAT101")
        #expect(module.color == .blue)
        #expect(repository.storage.count == 1)
    }

    @Test func createRejectsEmptyName() {
        let repository = FakeModuleRepository()
        let create = CreateModuleUseCase(repository: repository)

        #expect(throws: ModuleError.emptyName) {
            try create(name: "   ", code: "", color: .violet)
        }
        #expect(repository.storage.isEmpty)
    }

    @Test func updateChangesFields() throws {
        let repository = FakeModuleRepository()
        let create = CreateModuleUseCase(repository: repository)
        let update = UpdateModuleUseCase(repository: repository)
        let module = try create(name: "Physik", code: "", color: .violet)

        let updated = try update(module, name: "Physik II", code: "PHY2", color: .teal)

        #expect(updated.id == module.id)
        #expect(repository.storage.first?.name == "Physik II")
        #expect(repository.storage.first?.color == .teal)
    }

    @Test func deleteRemovesModule() throws {
        let repository = FakeModuleRepository()
        let create = CreateModuleUseCase(repository: repository)
        let delete = DeleteModuleUseCase(
            repository: repository,
            slideRepository: FakeSlideDocumentRepository(),
            noteRepository: FakeNoteRepository(),
            flashcardRepository: FakeFlashcardRepository(),
            studySheetRepository: FakeStudySheetRepository(),
            fileStorage: FakeFileStorage()
        )
        let module = try create(name: "Chemie", code: "", color: .green)

        try delete(module)

        #expect(repository.storage.isEmpty)
    }

    @Test func deletingModuleAlsoDeletesItsFlashcardsAndStudySheets() throws {
        let moduleRepository = FakeModuleRepository()
        let module = try CreateModuleUseCase(repository: moduleRepository)(
            name: "Biologie", code: "BIO1", color: .green
        )
        let foreignModuleID = UUID()
        let flashcards = FakeFlashcardRepository()
        let studySheets = FakeStudySheetRepository()
        flashcards.storage = [
            Flashcard(moduleID: module.id, front: "Frage 1", back: "Antwort 1"),
            Flashcard(moduleID: foreignModuleID, front: "Frage 2", back: "Antwort 2")
        ]
        studySheets.storage = [
            StudySheet(moduleID: module.id, title: "BIO Lernzettel", content: "# BIO", sourceNoteIDs: []),
            StudySheet(moduleID: foreignModuleID, title: "Andere", content: "# Andere", sourceNoteIDs: [])
        ]
        let delete = DeleteModuleUseCase(
            repository: moduleRepository,
            slideRepository: FakeSlideDocumentRepository(),
            noteRepository: FakeNoteRepository(),
            flashcardRepository: flashcards,
            studySheetRepository: studySheets,
            fileStorage: FakeFileStorage()
        )

        try delete(module)

        #expect(flashcards.storage.map(\.moduleID) == [foreignModuleID])
        #expect(studySheets.storage.map(\.moduleID) == [foreignModuleID])
    }

    @Test func listSortsByCreationDate() throws {
        let repository = FakeModuleRepository()
        let older = StudyModule(id: UUID(), name: "A", code: "", color: .violet, createdAt: Date(timeIntervalSince1970: 100))
        let newer = StudyModule(id: UUID(), name: "B", code: "", color: .violet, createdAt: Date(timeIntervalSince1970: 200))
        repository.storage = [newer, older]

        let result = try ListModulesUseCase(repository: repository)()

        #expect(result.map(\.name) == ["A", "B"])
    }
}
