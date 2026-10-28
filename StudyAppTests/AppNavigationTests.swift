import Foundation
import Testing
@testable import StudyApp

@MainActor
struct AppNavigationTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "AppNavigationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeNavigation() throws -> AppNavigation {
        AppNavigation(defaults: try makeDefaults())
    }

    @Test func startsWithoutDestination() throws {
        let navigation = try makeNavigation()
        #expect(navigation.destination == nil)
        #expect(navigation.currentLocation == nil)
        #expect(!navigation.canGoBack)
    }

    @Test func rememberedSectionIsRestoredPerModule() throws {
        let navigation = try makeNavigation()
        let analysis = UUID()
        let algebra = UUID()

        navigation.show(module: analysis, section: .notes)
        navigation.show(module: algebra, section: .slides)
        navigation.show(.module(analysis))

        #expect(navigation.currentLocation == .module(analysis, section: .notes))
        #expect(navigation.section(for: algebra) == .slides)
    }

    @Test func sectionShortcutNeedsASelectedModule() throws {
        let navigation = try makeNavigation()
        navigation.show(section: .notes)
        #expect(navigation.destination == nil)
        #expect(!navigation.canGoBack)

        let module = UUID()
        navigation.show(.module(module))
        navigation.show(section: .flashcards)
        #expect(navigation.section(for: module) == .flashcards)
    }

    @Test func backAndForwardWalkThroughHistory() throws {
        let navigation = try makeNavigation()
        let module = UUID()

        navigation.showCalendar()
        navigation.show(module: module, section: .overview)
        navigation.show(section: .notes)

        navigation.goBack()
        #expect(navigation.currentLocation == .module(module, section: .overview))
        navigation.goBack()
        #expect(navigation.currentLocation == .calendar)
        #expect(!navigation.canGoBack)

        navigation.goForward()
        navigation.goForward()
        #expect(navigation.currentLocation == .module(module, section: .notes))
        #expect(!navigation.canGoForward)
    }

    @Test func newNavigationClearsForwardHistory() throws {
        let navigation = try makeNavigation()
        let module = UUID()
        navigation.showCalendar()
        navigation.show(module: module, section: .overview)
        navigation.goBack()
        #expect(navigation.canGoForward)

        navigation.show(module: module, section: .slides)
        #expect(!navigation.canGoForward)
    }

    @Test func navigatingToTheCurrentLocationAddsNoHistory() throws {
        let navigation = try makeNavigation()
        navigation.showCalendar()
        navigation.showCalendar()
        navigation.show(.calendar)
        #expect(!navigation.canGoBack)
    }

    @Test func pruneRemovesDeletedModulesEverywhere() throws {
        let navigation = try makeNavigation()
        let deleted = UUID()
        let kept = UUID()

        navigation.show(module: deleted, section: .notes)
        navigation.showCalendar()
        navigation.show(module: kept, section: .overview)

        navigation.prune(validModuleIDs: [kept])
        #expect(navigation.destination == .module(kept))
        #expect(navigation.backStack == [.calendar])
        #expect(navigation.sections[deleted] == nil)

        navigation.prune(validModuleIDs: [])
        #expect(navigation.destination == nil)
    }

    @Test func stateSurvivesRestart() throws {
        let defaults = try makeDefaults()
        let module = UUID()

        let first = AppNavigation(defaults: defaults)
        first.show(module: module, section: .flashcards)

        let second = AppNavigation(defaults: defaults)
        #expect(second.destination == .module(module))
        #expect(second.section(for: module) == .flashcards)
        #expect(!second.canGoBack)
    }
}

@MainActor
struct AppNavigationTodayTests {
    private func makeDefaults() throws -> UserDefaults {
        let name = "AppNavigationTodayTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func todayIsPersistedAndRestored() throws {
        let defaults = try makeDefaults()
        let navigation = AppNavigation(defaults: defaults)
        navigation.showToday()
        #expect(navigation.currentLocation == .today)

        let restored = AppNavigation(defaults: defaults)
        #expect(restored.destination == .today)
    }

    @Test func gradesArePersistedAndRestored() throws {
        let defaults = try makeDefaults()
        AppNavigation(defaults: defaults).showGrades()
        #expect(AppNavigation(defaults: defaults).destination == .grades)
    }

    @Test func overviewsArePersistedAndRestored() throws {
        let defaults = try makeDefaults()
        let navigation = AppNavigation(defaults: defaults)
        navigation.showAssignments()
        #expect(AppNavigation(defaults: defaults).destination == .assignments)
        navigation.showExams()
        #expect(AppNavigation(defaults: defaults).destination == .exams)
    }

    @Test func storageKeyRoundTripsEveryDestination() {
        let destinations: [AppDestination] = [.today, .calendar, .assignments, .exams, .grades, .module(UUID())]
        for destination in destinations {
            #expect(AppDestination(storageKey: destination.storageKey) == destination)
        }
        #expect(AppDestination(storageKey: "unknown") == nil)
    }

    @Test func showingAModuleWithIntentKeepsTheIntentForTheModuleView() throws {
        let navigation = AppNavigation(defaults: try makeDefaults())
        let module = UUID()
        navigation.show(module: module, section: .slides, intent: .resumeSlides)

        #expect(navigation.currentLocation == .module(module, section: .slides))
        #expect(navigation.pendingIntent == .resumeSlides)
    }

    @Test func pruningTheCurrentModuleDropsItsIntent() throws {
        let navigation = AppNavigation(defaults: try makeDefaults())
        let module = UUID()
        navigation.show(module: module, section: .notes, intent: .selectNote(UUID()))
        navigation.prune(validModuleIDs: [])

        #expect(navigation.destination == nil)
        #expect(navigation.pendingIntent == nil)
    }
}

struct ModuleTabTests {
    @Test func everySectionBelongsToExactlyTheTabThatListsIt() {
        let listed = ModuleTab.allCases.flatMap(\.sections)
        #expect(listed.count == ModuleSection.allCases.count)
        #expect(Set(listed) == Set(ModuleSection.allCases))
        for tab in ModuleTab.allCases {
            #expect(tab.sections.allSatisfy { $0.tab == tab })
        }
    }

    @Test func tabsOpenTheirMainSectionFirst() {
        #expect(ModuleTab.overview.sections.first == .overview)
        #expect(ModuleTab.material.sections.first == .slides)
        #expect(ModuleTab.learning.sections.first == .notes)
    }
}

@MainActor
struct QuickNavigatorIndexTests {
    private let analysis = StudyModule(id: UUID(), name: "Analysis I", code: "MAT101", color: .blue, createdAt: Date())
    private let algebra = StudyModule(id: UUID(), name: "Lineare Algebra", code: "MAT102", color: .teal, createdAt: Date())

    @Test func indexContainsTheOverviewsAndEverySectionOfEveryModule() {
        let items = QuickNavigatorIndex.items(modules: [analysis, algebra])
        #expect(items.count == 5 + 2 * ModuleSection.allCases.count)
        #expect(items.map(\.location).prefix(5) == [.today, .calendar, .assignments, .exams, .grades])
        #expect(Set(items.map(\.id)).count == items.count)
    }

    @Test func notesAreFoundByContentButHiddenWithoutQuery() {
        let note = LectureNote(
            id: UUID(), slideDocumentID: analysis.id, title: "Vorlesung vom 19.10.2026",
            content: "Der Satz von Rolle gilt für stetige Funktionen.", format: .markdown,
            pageNumber: nil, createdAt: Date(), updatedAt: Date()
        )
        let reference = NoteReference(note: note, module: analysis, sourceTitle: note.title)
        let items = QuickNavigatorIndex.items(modules: [analysis], notes: [reference])

        #expect(!QuickNavigatorIndex.filter(items, query: "").contains { $0.isNote })
        let result = QuickNavigatorIndex.filter(items, query: "rolle")
        #expect(result.map(\.noteID) == [note.id])
        #expect(result.first?.location == .module(analysis.id, section: .notes))
    }

    @Test func modulesRankBeforeNotes() {
        let note = LectureNote(
            id: UUID(), slideDocumentID: algebra.id, title: "Analysis-Bezug",
            content: "", format: .markdown, pageNumber: nil, createdAt: Date(), updatedAt: Date()
        )
        let items = QuickNavigatorIndex.items(
            modules: [analysis, algebra],
            notes: [NoteReference(note: note, module: algebra, sourceTitle: note.title)]
        )
        let result = QuickNavigatorIndex.filter(items, query: "analysis")
        #expect(result.last?.isNote == true)
        #expect(result.first?.location == .module(analysis.id, section: .overview))
    }

    @Test func filterRequiresAllTokensAndIgnoresCase() {
        let items = QuickNavigatorIndex.items(modules: [analysis, algebra])
        let result = QuickNavigatorIndex.filter(items, query: "karteik ANA")
        #expect(result.map(\.location) == [.module(analysis.id, section: .flashcards)])
    }

    @Test func emptyQueryKeepsEveryDestination() {
        let items = QuickNavigatorIndex.items(modules: [analysis])
        #expect(QuickNavigatorIndex.filter(items, query: "  ").count == items.count)
    }

    @Test func codeIsSearchable() {
        let items = QuickNavigatorIndex.items(modules: [analysis, algebra])
        let result = QuickNavigatorIndex.filter(items, query: "MAT102 notizen")
        #expect(result.map(\.location) == [.module(algebra.id, section: .notes)])
    }
}
