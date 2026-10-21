import Foundation

@MainActor
struct ListModulesUseCase {
    let repository: any ModuleRepository

    func callAsFunction() throws -> [StudyModule] {
        try repository.all().sorted { $0.createdAt < $1.createdAt }
    }
}

@MainActor
struct CreateModuleUseCase {
    let repository: any ModuleRepository

    @discardableResult
    func callAsFunction(name: String, code: String, color: ModuleColor, semester: Semester? = nil) throws -> StudyModule {
        let cleanName = name.trimmed
        guard !cleanName.isEmpty else { throw ModuleError.emptyName }

        let module = StudyModule(
            id: UUID(),
            name: cleanName,
            code: code.trimmed,
            color: color,
            createdAt: Date(),
            semester: semester
        )
        try repository.add(module)
        return module
    }
}

@MainActor
struct UpdateModuleUseCase {
    let repository: any ModuleRepository

    @discardableResult
    func callAsFunction(
        _ module: StudyModule,
        name: String,
        code: String,
        color: ModuleColor,
        semester: Semester? = nil,
        isArchived: Bool? = nil
    ) throws -> StudyModule {
        let cleanName = name.trimmed
        guard !cleanName.isEmpty else { throw ModuleError.emptyName }

        var updated = module
        updated.name = cleanName
        updated.code = code.trimmed
        updated.color = color
        if let semester { updated.semester = semester }
        if let isArchived { updated.isArchived = isArchived }
        try repository.update(updated)
        return updated
    }
}

/// Archiviert Module oder holt sie zurück. Noten, Folien und Notizen bleiben unverändert.
@MainActor
struct SetModulesArchivedUseCase {
    let repository: any ModuleRepository

    /// - Returns: Anzahl der tatsächlich geänderten Module.
    @discardableResult
    func callAsFunction(_ modules: [StudyModule], archived: Bool) throws -> Int {
        var changed = 0
        for module in modules where module.isArchived != archived {
            var updated = module
            updated.isArchived = archived
            try repository.update(updated)
            changed += 1
        }
        return changed
    }
}

/// Gruppierung der Module nach Semestern für Seitenleiste und Notenübersicht.
enum SemesterOverview {
    struct Group: Identifiable, Equatable {
        let semester: Semester
        let modules: [StudyModule]
        var id: String { semester.rawValue }
    }

    /// Neueste Semester zuerst, innerhalb eines Semesters in der gespeicherten Reihenfolge.
    static func groups(_ modules: [StudyModule]) -> [Group] {
        Dictionary(grouping: modules, by: \.semester)
            .map { Group(semester: $0.key, modules: $0.value) }
            .sorted { $0.semester > $1.semester }
    }

    /// Vergangene Semester, in denen noch nicht archivierte Module liegen – Kandidaten zum Abschließen.
    static func finishedSemestersWithActiveModules(_ modules: [StudyModule], now: Date, calendar: Calendar = .current) -> [Semester] {
        let current = Semester(containing: now, calendar: calendar)
        let finished = modules.filter { !$0.isArchived && $0.semester < current }.map(\.semester)
        return Set(finished).sorted(by: >)
    }
}

/// Deletes a module together with its slides, lecture notes, flashcards, and study sheets.
/// Calendar events stay, only their link to the module is removed.
@MainActor
struct DeleteModuleUseCase {
    let repository: any ModuleRepository
    let slideRepository: any SlideDocumentRepository
    let noteRepository: any NoteRepository
    let flashcardRepository: any FlashcardRepository
    let studySheetRepository: any StudySheetRepository
    let fileStorage: any FileStorage
    var calendarRepository: (any StudyCalendarRepository)? = nil
    var assignmentRepository: (any AssignmentRepository)? = nil

    func callAsFunction(_ module: StudyModule) throws {
        let deleteSlides = DeleteSlideDocumentUseCase(
            repository: slideRepository,
            noteRepository: noteRepository,
            storage: fileStorage
        )
        for document in try slideRepository.documents(forModule: module.id) {
            try deleteSlides(document)
        }
        // Free module notes are stored under the module's ID (see `LectureNote`).
        try noteRepository.deleteNotes(forSlideDocument: module.id)
        try flashcardRepository.deleteCards(forModule: module.id)
        try studySheetRepository.deleteSheets(forModule: module.id)
        try calendarRepository?.clearModuleLinks(forModule: module.id)
        try assignmentRepository?.deleteAssignments(forModule: module.id)
        try repository.delete(id: module.id)
    }
}
