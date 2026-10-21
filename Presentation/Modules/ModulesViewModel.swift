import Foundation
import Observation

/// Eingabewerte des Modul-Editors.
struct ModuleDraft {
    var id: UUID?
    var name: String = ""
    var code: String = ""
    var color: ModuleColor = .violet
    /// Freitext, damit „7,5“ oder ein leeres Feld möglich sind.
    var creditsText: String = ""
    var gradeText: String = ""
    var semester = Semester(containing: .now)
    var isArchived = false
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
            ModuleDraft(
                id: module.id,
                name: module.name,
                code: module.code,
                color: module.color,
                creditsText: module.credits.map { GradeScale.formatCredits($0) } ?? "",
                gradeText: module.grade.map { GradeScale.format($0) } ?? "",
                semester: module.semester,
                isArchived: module.isArchived
            )
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
    private let updateGrade: UpdateModuleGradeUseCase
    private let archiveModules: SetModulesArchivedUseCase
    private let settings: any StudySettingsStore

    init(
        repository: any ModuleRepository,
        slideRepository: any SlideDocumentRepository,
        noteRepository: any NoteRepository,
        flashcardRepository: any FlashcardRepository,
        studySheetRepository: any StudySheetRepository,
        fileStorage: any FileStorage,
        calendarRepository: (any StudyCalendarRepository)? = nil,
        assignmentRepository: (any AssignmentRepository)? = nil,
        settings: any StudySettingsStore
    ) {
        self.settings = settings
        listModules = ListModulesUseCase(repository: repository)
        createModule = CreateModuleUseCase(repository: repository)
        updateModule = UpdateModuleUseCase(repository: repository)
        updateGrade = UpdateModuleGradeUseCase(repository: repository)
        archiveModules = SetModulesArchivedUseCase(repository: repository)
        deleteModule = DeleteModuleUseCase(
            repository: repository,
            slideRepository: slideRepository,
            noteRepository: noteRepository,
            flashcardRepository: flashcardRepository,
            studySheetRepository: studySheetRepository,
            fileStorage: fileStorage,
            calendarRepository: calendarRepository,
            assignmentRepository: assignmentRepository
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
            // Erst prüfen, dann speichern: sonst entstünde bei einer ungültigen Note ein halb angelegtes Modul.
            let (credits, grade) = try Self.parseGrade(creditsText: draft.creditsText, gradeText: draft.gradeText)
            var saved: StudyModule
            if let id = draft.id {
                guard let existing = module(withID: id) else {
                    throw ModuleError.notFound
                }
                saved = try updateModule(
                    existing, name: draft.name, code: draft.code, color: draft.color,
                    semester: draft.semester, isArchived: draft.isArchived
                )
            } else {
                saved = try createModule(name: draft.name, code: draft.code, color: draft.color, semester: draft.semester)
            }
            saved = try updateGrade(saved, credits: credits, grade: grade)
            // Ein bewusst angelegtes Modul darf wieder mit dem Kalender abgeglichen werden.
            settings.ignoredCourseKeys.remove(DetectModuleCandidatesUseCase.moduleKey(for: saved))
            load()
            return saved
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: Semester-Archiv

    /// Module des laufenden Studiums für Seitenleiste und Startseite.
    var activeModules: [StudyModule] { modules.filter { !$0.isArchived } }

    var archivedGroups: [SemesterOverview.Group] {
        SemesterOverview.groups(modules.filter(\.isArchived))
    }

    /// Vergangene Semester mit noch aktiven Modulen, für den Hinweis „Semester abschließen“.
    func finishedSemesters(now: Date = .now) -> [Semester] {
        SemesterOverview.finishedSemestersWithActiveModules(modules, now: now)
    }

    func setArchived(_ module: StudyModule, _ archived: Bool) {
        setArchived([module], archived)
    }

    /// Archiviert alle aktiven Module eines Semesters bzw. holt alle archivierten zurück.
    func setArchived(semester: Semester, _ archived: Bool) {
        setArchived(modules.filter { $0.semester == semester }, archived)
    }

    private func setArchived(_ modules: [StudyModule], _ archived: Bool) {
        do {
            try archiveModules(modules, archived: archived)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Noten und ECTS

    var gradeSummary: GradeSummary { GradeSummary(modules: modules) }

    /// Speichert Note und Leistungspunkte aus Texteingaben. Gibt bei ungültigen Werten `false` zurück.
    @discardableResult
    func updateGrade(of module: StudyModule, creditsText: String, gradeText: String) -> Bool {
        do {
            let (credits, grade) = try Self.parseGrade(creditsText: creditsText, gradeText: gradeText)
            try updateGrade(module, credits: credits, grade: grade)
            load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Liest „7,5“ bzw. „1,7“; leerer Text bedeutet „nicht angegeben“.
    static func parseGrade(creditsText: String, gradeText: String) throws -> (credits: Double?, grade: Double?) {
        guard let credits = GradeScale.parse(creditsText) else { throw GradeError.invalidCredits }
        guard let grade = GradeScale.parse(gradeText) else { throw GradeError.invalidGrade }
        if let grade, !GradeScale.range.contains(grade) { throw GradeError.invalidGrade }
        if let credits, !(0...GradeScale.maximumCredits).contains(credits) { throw GradeError.invalidCredits }
        return (credits, grade)
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
