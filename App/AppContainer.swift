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
    let assignmentRepository: any AssignmentRepository
    let calendarFeedLoader: any CalendarFeedLoader
    let calendarEventParser: any CalendarEventParsing
    let fileStorage: any FileStorage
    let pdfInspector: any PDFInspector
    let studIPService: any StudIPService
    let studIPAccountStore: any StudIPAccountStore
    let courseFileRepository: any CourseFileRepository
    let notificationScheduler: any NotificationScheduling
    /// Einstellungen und Lesefortschritt; im Speicher für Tests und Previews, sonst in `UserDefaults`.
    let preferences: any StudySettingsStore & ReadingProgressStore

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
        assignmentRepository = SwiftDataAssignmentRepository(context: context)
        courseFileRepository = SwiftDataCourseFileRepository(context: context)
        notificationScheduler = UserNotificationScheduler()
        calendarFeedLoader = URLSessionCalendarFeedLoader()
        calendarEventParser = ICalendarFeedParser()
        pdfInspector = PDFKitInspector()
        studIPService = StudIPJSONAPIClient()
        if inMemory {
            preferences = InMemoryStudyPreferences()
            studIPAccountStore = InMemoryStudIPAccountStore()
        } else {
            preferences = UserDefaultsStudyPreferences()
            studIPAccountStore = KeychainStudIPAccountStore()
        }

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
            fileStorage: fileStorage,
            calendarRepository: studyCalendarRepository,
            assignmentRepository: assignmentRepository,
            courseFileRepository: courseFileRepository,
            settings: preferences
        )
    }

    func makeNotificationsViewModel() -> NotificationsViewModel {
        NotificationsViewModel(
            scheduler: notificationScheduler,
            modules: moduleRepository,
            calendar: studyCalendarRepository,
            assignments: assignmentRepository,
            store: preferences
        )
    }

    func makeAssignmentsViewModel() -> AssignmentsViewModel {
        AssignmentsViewModel(repository: assignmentRepository)
    }

    func makeStudyCalendarViewModel() -> StudyCalendarViewModel {
        StudyCalendarViewModel(
            repository: studyCalendarRepository,
            moduleRepository: moduleRepository,
            feedLoader: calendarFeedLoader,
            parser: calendarEventParser,
            settings: preferences
        )
    }

    func makeStudIPViewModel() -> StudIPViewModel {
        StudIPViewModel(
            service: studIPService,
            store: studIPAccountStore,
            moduleRepository: moduleRepository,
            slideRepository: slideRepository,
            importer: ImportSlideDocumentUseCase(repository: slideRepository, storage: fileStorage, inspector: pdfInspector),
            fileRepository: courseFileRepository,
            storage: fileStorage
        )
    }

    func makeCourseFilesViewModel(module: StudyModule) -> CourseFilesViewModel {
        CourseFilesViewModel(
            module: module,
            repository: courseFileRepository,
            slideRepository: slideRepository,
            service: studIPService,
            storage: fileStorage,
            store: studIPAccountStore
        )
    }

    func makeTodayViewModel() -> TodayViewModel {
        TodayViewModel(
            moduleRepository: moduleRepository,
            slideRepository: slideRepository,
            noteRepository: noteRepository,
            flashcardRepository: flashcardRepository
        )
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
            readingProgress: preferences,
            notesViewModelFactory: { [noteRepository] document in
                NotesViewModel(document: document, repository: noteRepository)
            }
        )
    }
}
