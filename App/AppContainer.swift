import Foundation
import SwiftData

/// Composition Root: der einzige Ort, der Data-Implementierungen mit der Domain verdrahtet.
@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let moduleRepository: any ModuleRepository
    let slideRepository: any SlideDocumentRepository
    let noteRepository: any NoteRepository
    let flashcardRepository: any FlashcardRepository
    let studySheetRepository: any StudySheetRepository
    let studyCalendarRepository: any StudyCalendarRepository
    let fileStorage: any FileStorage
    let pdfInspector: any PDFInspector

    init(inMemory: Bool = false) throws {
        let container = try Persistence.makeContainer(inMemory: inMemory)
        let context = container.mainContext

        modelContainer = container
        moduleRepository = SwiftDataModuleRepository(context: context)
        slideRepository = SwiftDataSlideDocumentRepository(context: context)
        noteRepository = SwiftDataNoteRepository(context: context)
        flashcardRepository = SwiftDataFlashcardRepository(context: context)
        studySheetRepository = SwiftDataStudySheetRepository(context: context)
        studyCalendarRepository = SwiftDataStudyCalendarRepository(context: context)
        pdfInspector = PDFKitInspector()

        if inMemory {
            // Für Previews und Tests: Dateien landen im temporären Ordner.
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "StudyApp-\(UUID().uuidString)", directoryHint: .isDirectory)
            fileStorage = try LocalFileStorage(baseDirectory: directory)
        } else {
            fileStorage = try LocalFileStorage.applicationDefault()
        }
    }

    func makeModulesViewModel() -> ModulesViewModel {
        ModulesViewModel(
            repository: moduleRepository,
            slideRepository: slideRepository,
            noteRepository: noteRepository,
            flashcardRepository: flashcardRepository,
            studySheetRepository: studySheetRepository,
            fileStorage: fileStorage
        )
    }

    func makeStudyCalendarViewModel() -> StudyCalendarViewModel {
        StudyCalendarViewModel(repository: studyCalendarRepository, moduleRepository: moduleRepository)
    }

    func makeLearningViewModel(module: StudyModule) -> LearningViewModel {
        LearningViewModel(
            module: module,
            slideRepository: slideRepository,
            noteRepository: noteRepository,
            flashcardRepository: flashcardRepository,
            studySheetRepository: studySheetRepository
        )
    }

    func makeSlidesViewModel(moduleID: UUID) -> SlidesViewModel {
        SlidesViewModel(
            moduleID: moduleID,
            repository: slideRepository,
            noteRepository: noteRepository,
            storage: fileStorage,
            inspector: pdfInspector,
            notesViewModelFactory: { [noteRepository] document in
                NotesViewModel(document: document, repository: noteRepository)
            }
        )
    }
}
