import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
struct ModuleNoteTests {
    private let moduleID = UUID()
    private let clock = TestClock()
    private let repository = FakeNoteRepository()

    @Test func moduleNotesAreStoredUnderTheModuleID() throws {
        let note = try CreateModuleNoteUseCase(repository: repository, now: { clock.now })(
            moduleID: moduleID, title: "  Vorlesung vom 19.10.2026 ", content: "Rolle"
        )
        #expect(note.slideDocumentID == moduleID)
        #expect(note.isModuleNote(of: moduleID))
        #expect(note.title == "Vorlesung vom 19.10.2026")
        #expect(note.format == .markdown)
        #expect(try repository.notes(forSlideDocument: moduleID).map(\.id) == [note.id])
    }

    @Test func emptyTitleFallsBack() throws {
        let note = try CreateModuleNoteUseCase(repository: repository)(moduleID: moduleID, title: "   ")
        #expect(note.title == CreateModuleNoteUseCase.fallbackTitle)
    }

    @Test func updateChangesOnlyOnRealEdits() throws {
        let created = try CreateModuleNoteUseCase(repository: repository, now: { clock.now })(moduleID: moduleID, title: "A")
        let update = UpdateNoteUseCase(repository: repository, now: { clock.now })

        clock.advance(by: 60)
        let unchanged = try update(created, title: "A", content: "", format: .markdown)
        #expect(unchanged.updatedAt == created.updatedAt)
        #expect(repository.updateCount == 0)

        let edited = try update(created, title: " ", content: "Neu", format: .latex)
        #expect(edited.title == "A")
        #expect(edited.content == "Neu")
        #expect(edited.format == .latex)
        #expect(edited.updatedAt == clock.now)
        #expect(repository.updateCount == 1)
    }

    @Test func editingSessionAutosavesAndReportsBack() async throws {
        let created = try CreateModuleNoteUseCase(repository: repository)(moduleID: moduleID, title: "Notiz")
        var reported: LectureNote?
        let session = NoteEditingSession(note: created, repository: repository, autosaveDelay: .milliseconds(10)) {
            reported = $0
        }
        session.content = "Inhalt"
        session.noteDidChange()
        #expect(session.saveState == .pending)
        try await Task.sleep(for: .milliseconds(80))

        #expect(session.saveState == .saved)
        #expect(reported?.content == "Inhalt")
        #expect(try repository.notes(forSlideDocument: moduleID).first?.content == "Inhalt")
    }

    @Test func deletingAModuleRemovesItsFreeNotesAndCalendarLinks() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let context = container.mainContext
            let modules = SwiftDataModuleRepository(context: context)
            let notes = SwiftDataNoteRepository(context: context)
            let calendar = SwiftDataStudyCalendarRepository(context: context)
            let module = StudyModule(id: UUID(), name: "Analysis", code: "", color: .blue, createdAt: Date())
            try modules.add(module)
            try CreateModuleNoteUseCase(repository: notes)(moduleID: module.id, title: "Vorlesung")

            let source = CalendarSource(id: UUID(), name: "Plan", url: nil, lastSyncedAt: nil, kind: .file)
            try calendar.save(source: source)
            try calendar.replaceEvents(forSource: source.id, with: [
                StudyCalendarEvent(
                    id: UUID(), externalID: "a", sourceID: source.id, title: "Analysis", details: "", location: "",
                    startDate: Date(), endDate: Date().addingTimeInterval(3_600), moduleID: module.id
                )
            ])

            try DeleteModuleUseCase(
                repository: modules,
                slideRepository: SwiftDataSlideDocumentRepository(context: context),
                noteRepository: notes,
                flashcardRepository: SwiftDataFlashcardRepository(context: context),
                studySheetRepository: SwiftDataStudySheetRepository(context: context),
                fileStorage: FakeFileStorage(),
                calendarRepository: calendar
            )(module)

            #expect(try notes.notes(forSlideDocument: module.id).isEmpty)
            #expect(try calendar.events().count == 1)
            #expect(try calendar.events().first?.moduleID == nil)
        }
    }

    @Test func lectureNoteIsCreatedOnceAndReused() throws {
        let module = StudyModule(id: moduleID, name: "Analysis I", code: "", color: .blue, createdAt: Date())
        let viewModel = LearningViewModel(
            module: module,
            slideRepository: FakeSlideDocumentRepository(),
            noteRepository: repository,
            flashcardRepository: FakeFlashcardRepository(),
            studySheetRepository: FakeStudySheetRepository()
        )
        viewModel.load()
        let start = Date(timeIntervalSince1970: 1_792_000_000)

        let first = try #require(viewModel.openLectureNote(start: start, eventTitle: "Analysis I (Übung)"))
        #expect(first.title.hasPrefix("Übung vom "))
        #expect(viewModel.selectedNoteID == first.id)

        let second = viewModel.openLectureNote(start: start, eventTitle: "Analysis I (Übung)")
        #expect(second?.id == first.id)
        #expect(viewModel.notes.count == 1)
    }
}

@MainActor
struct LectureAutopilotTests {
    private struct Setup {
        let autopilot: LectureAutopilot
        let navigation: AppNavigation
        let calendar: StudyCalendarViewModel
        let modules: ModulesViewModel
        let module: StudyModule
        let settings: InMemoryStudyPreferences
        let container: ModelContainer
    }

    private func makeSetup(now: Date, eventStart: Date) throws -> Setup {
        let settings = InMemoryStudyPreferences()
        let navigationSuite = "LectureAutopilotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: navigationSuite))
        defaults.removePersistentDomain(forName: navigationSuite)
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let moduleRepository = SwiftDataModuleRepository(context: context)
        let calendarRepository = SwiftDataStudyCalendarRepository(context: context)
        let module = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: Date())
        try moduleRepository.add(module)
        let source = CalendarSource(id: UUID(), name: "Plan", url: nil, lastSyncedAt: nil, kind: .file)
        try calendarRepository.save(source: source)
        try calendarRepository.replaceEvents(forSource: source.id, with: [
            StudyCalendarEvent(
                id: UUID(), externalID: "vl", sourceID: source.id, title: "Analysis I", details: "", location: "",
                startDate: eventStart, endDate: eventStart.addingTimeInterval(5_400), moduleID: module.id
            )
        ])
        let calendar = StudyCalendarViewModel(
            repository: calendarRepository,
            moduleRepository: moduleRepository,
            feedLoader: StubFeedLoader(),
            parser: ICalendarFeedParser(),
            settings: settings,
            now: { now }
        )
        let modules = ModulesViewModel(
            repository: moduleRepository,
            slideRepository: SwiftDataSlideDocumentRepository(context: context),
            noteRepository: SwiftDataNoteRepository(context: context),
            flashcardRepository: SwiftDataFlashcardRepository(context: context),
            studySheetRepository: SwiftDataStudySheetRepository(context: context),
            fileStorage: FakeFileStorage(),
            settings: settings
        )
        calendar.load()
        modules.load()
        let navigation = AppNavigation(defaults: defaults)
        let autopilot = LectureAutopilot(navigation: navigation, calendar: calendar, modules: modules, settings: settings)
        return Setup(autopilot: autopilot, navigation: navigation, calendar: calendar, modules: modules, module: module, settings: settings, container: container)
    }

    @Test func launchingDuringALectureOpensItsSlides() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let setup = try makeSetup(now: now, eventStart: now.addingTimeInterval(-600))
        defer { withExtendedLifetime(setup.container) {} }

        #expect(setup.autopilot.run(isLaunch: true))
        #expect(setup.navigation.currentLocation == .module(setup.module.id, section: .slides))
        #expect(setup.navigation.pendingIntent == .resumeSlides)
    }

    @Test func reactivatingOpensEachLectureOnlyOnce() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let setup = try makeSetup(now: now, eventStart: now.addingTimeInterval(-600))
        defer { withExtendedLifetime(setup.container) {} }

        #expect(setup.autopilot.run(isLaunch: false))
        setup.navigation.showCalendar()
        #expect(!setup.autopilot.run(isLaunch: false))
        #expect(setup.navigation.destination == .calendar)
    }

    @Test func nothingHappensOutsideLecturesOrWhenDisabled() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let later = try makeSetup(now: now, eventStart: now.addingTimeInterval(3 * 3_600))
        defer { withExtendedLifetime(later.container) {} }
        #expect(!later.autopilot.run(isLaunch: true))
        #expect(later.navigation.destination == nil)

        let running = try makeSetup(now: now, eventStart: now)
        defer { withExtendedLifetime(running.container) {} }
        running.settings.autoOpenLecture = false
        #expect(!running.autopilot.run(isLaunch: true))
    }
}

@MainActor
struct ModuleBadgeTests {
    @Test func initialsSkipRomanNumeralsAndFillers() {
        #expect(ModuleBadge.initials(for: "Lineare Algebra II") == "LA")
        #expect(ModuleBadge.initials(for: "Analysis I") == "An")
        #expect(ModuleBadge.initials(for: "Mathematik für Informatiker") == "MI")
        #expect(ModuleBadge.initials(for: "") == "?")
    }
}
