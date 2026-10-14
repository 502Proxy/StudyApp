import Foundation
import Observation

/// Eingabewerte des Modul-Editors.
struct ModuleDraft {
    var id: UUID?
    var name: String = ""
    var code: String = ""
    var color: ModuleColor = .violet
}

enum ModuleEditorMode: Identifiable {
    case create
    case edit(StudyModule)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let module): module.id.uuidString
        }
    }

    var draft: ModuleDraft {
        switch self {
        case .create:
            ModuleDraft()
        case .edit(let module):
            ModuleDraft(id: module.id, name: module.name, code: module.code, color: module.color)
        }
    }

    var title: String {
        switch self {
        case .create: "Neues Modul"
        case .edit: "Modul bearbeiten"
        }
    }
}

@MainActor
@Observable
final class ModulesViewModel {
    private(set) var modules: [StudyModule] = []
    var selectedID: UUID?
    var editorMode: ModuleEditorMode?
    var errorMessage: String?

    private let listModules: ListModulesUseCase
    private let createModule: CreateModuleUseCase
    private let updateModule: UpdateModuleUseCase
    private let deleteModule: DeleteModuleUseCase

    init(
        repository: any ModuleRepository,
        slideRepository: any SlideDocumentRepository,
        noteRepository: any NoteRepository,
        flashcardRepository: any FlashcardRepository,
        studySheetRepository: any StudySheetRepository,
        fileStorage: any FileStorage
    ) {
        listModules = ListModulesUseCase(repository: repository)
        createModule = CreateModuleUseCase(repository: repository)
        updateModule = UpdateModuleUseCase(repository: repository)
        deleteModule = DeleteModuleUseCase(
            repository: repository,
            slideRepository: slideRepository,
            noteRepository: noteRepository,
            flashcardRepository: flashcardRepository,
            studySheetRepository: studySheetRepository,
            fileStorage: fileStorage
        )
    }

    var selectedModule: StudyModule? {
        modules.first { $0.id == selectedID }
    }

    func load() {
        do {
            modules = try listModules()
            if let selectedID, !modules.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Speichert Anlegen oder Bearbeiten. Gibt `true` zurück, wenn der Editor schließen darf.
    func save(_ draft: ModuleDraft) -> Bool {
        do {
            if let id = draft.id {
                guard let existing = modules.first(where: { $0.id == id }) else {
                    throw ModuleError.notFound
                }
                try updateModule(existing, name: draft.name, code: draft.code, color: draft.color)
            } else {
                let created = try createModule(name: draft.name, code: draft.code, color: draft.color)
                selectedID = created.id
            }
            load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete(_ module: StudyModule) {
        do {
            try deleteModule(module)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
