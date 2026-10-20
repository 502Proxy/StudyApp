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
    var editorMode: ModuleEditorMode?
    var errorMessage: String?

    private let listModules: ListModulesUseCase
    private let createModule: CreateModuleUseCase
    private let updateModule: UpdateModuleUseCase
    private let deleteModule: DeleteModuleUseCase
    private let settings: any StudySettingsStore

    init(
        repository: any ModuleRepository,
        slideRepository: any SlideDocumentRepository,
        noteRepository: any NoteRepository,
        flashcardRepository: any FlashcardRepository,
        studySheetRepository: any StudySheetRepository,
        fileStorage: any FileStorage,
        calendarRepository: (any StudyCalendarRepository)? = nil,
        settings: any StudySettingsStore
    ) {
        self.settings = settings
        listModules = ListModulesUseCase(repository: repository)
        createModule = CreateModuleUseCase(repository: repository)
        updateModule = UpdateModuleUseCase(repository: repository)
        deleteModule = DeleteModuleUseCase(
            repository: repository,
            slideRepository: slideRepository,
            noteRepository: noteRepository,
            flashcardRepository: flashcardRepository,
            studySheetRepository: studySheetRepository,
            fileStorage: fileStorage,
            calendarRepository: calendarRepository
        )
    }

    func module(withID id: UUID) -> StudyModule? {
        modules.first { $0.id == id }
    }

    func load() {
        do {
            modules = try listModules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Speichert Anlegen oder Bearbeiten. Gibt das gespeicherte Modul zurück, bei einem Fehler `nil`
    /// (der Editor bleibt dann offen). Die Auswahl in der Seitenleiste verwaltet `AppNavigation`.
    @discardableResult
    func save(_ draft: ModuleDraft) -> StudyModule? {
        do {
            let saved: StudyModule
            if let id = draft.id {
                guard let existing = module(withID: id) else {
                    throw ModuleError.notFound
                }
                saved = try updateModule(existing, name: draft.name, code: draft.code, color: draft.color)
            } else {
                saved = try createModule(name: draft.name, code: draft.code, color: draft.color)
            }
            // Ein bewusst angelegtes Modul darf wieder mit dem Kalender abgeglichen werden.
            settings.ignoredCourseKeys.remove(DetectModuleCandidatesUseCase.moduleKey(for: saved))
            load()
            return saved
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func delete(_ module: StudyModule) {
        do {
            try deleteModule(module)
            // Ein gelöschtes Modul soll nicht beim nächsten Kalenderabgleich wieder entstehen.
            settings.ignoredCourseKeys.insert(DetectModuleCandidatesUseCase.moduleKey(for: module))
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
