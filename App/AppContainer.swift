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
    let studIPScheduleService: any StudIPScheduleService
    let studIPAccountStore: any StudIPAccountStore
    let courseFileRepository: any CourseFileRepository
    let backupArchiver: any BackupArchiving
    let backupFolder: any BackupFolder
    let notificationScheduler: any NotificationScheduling
    let examRepository: any ExamRepository
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
        examRepository = SwiftDataExamRepository(context: context)
        calendarFeedLoader = URLSessionCalendarFeedLoader()
        calendarEventParser = ICalendarFeedParser()
        pdfInspector = PDFKitInspector()
        // One client serves every Stud.IP port; features depend only on the port they use.
        let studIPClient = StudIPJSONAPIClient()
        studIPService = studIPClient
        studIPScheduleService = studIPClient
        if inMemory {
            preferences = InMemoryStudyPreferences()
            studIPAccountStore = InMemoryStudIPAccountStore()
        } else {
            preferences = UserDefaultsStudyPreferences()
            studIPAccountStore = KeychainStudIPAccountStore()
        }

        backupArchiver = AppleArchiveBackupArchiver()
        if inMemory {
            // Für Previews und Tests: Dateien landen im temporären Ordner.
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "StudyApp-\(UUID().uuidString)", directoryHint: .isDirectory)
            fileStorage = try LocalFileStorage(baseDirectory: directory)
            backupFolder = try LocalBackupFolder(directory: directory.appending(path: "Backups", directoryHint: .isDirectory))
        } else {
            fileStorage = try LocalFileStorage.applicationDefault()
            backupFolder = try LocalBackupFolder.applicationDefault()
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
            examRepository: examRepository,
            settings: preferences
        )
    }

    /// Every repository holding user data, for operations such as backups that touch all of them.
    var studyDataRepositories: StudyDataRepositories {
        StudyDataRepositories(
            modules: moduleRepository,
            slides: slideRepository,
            notes: noteRepository,
            flashcards: flashcardRepository,
            studySheets: studySheetRepository,
            assignments: assignmentRepository,
            calendar: studyCalendarRepository,
            courseFiles: courseFileRepository,
            exams: examRepository,
            files: fileStorage
        )
    }

    func makeBackupViewModel() -> BackupViewModel {
        BackupViewModel(
            repositories: studyDataRepositories,
            archiver: backupArchiver,
            folder: backupFolder,
            settings: preferences,
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
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

    func makeExamsViewModel() -> ExamsViewModel {
        ExamsViewModel(
            exams: examRepository,
            calendarRepository: studyCalendarRepository,
            modules: moduleRepository,
            slides: slideRepository,
            flashcards: flashcardRepository
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
            storage: fileStorage,
            timetableSync: SyncStudIPTimetableUseCase(service: studIPScheduleService, repository: studyCalendarRepository),
            settings: preferences
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
