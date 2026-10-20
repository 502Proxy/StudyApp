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
    func callAsFunction(name: String, code: String, color: ModuleColor) throws -> StudyModule {
        let cleanName = name.trimmed
        guard !cleanName.isEmpty else { throw ModuleError.emptyName }

        let module = StudyModule(
            id: UUID(),
            name: cleanName,
            code: code.trimmed,
            color: color,
            createdAt: Date()
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
        color: ModuleColor
    ) throws -> StudyModule {
        let cleanName = name.trimmed
        guard !cleanName.isEmpty else { throw ModuleError.emptyName }

        var updated = module
        updated.name = cleanName
        updated.code = code.trimmed
        updated.color = color
        try repository.update(updated)
        return updated
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
