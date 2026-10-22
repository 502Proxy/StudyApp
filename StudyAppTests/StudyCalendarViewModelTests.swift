import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
final class StubFeedLoader: CalendarFeedLoader {
    var data = Data()
    func load(from url: URL) async throws -> Data { data }
}

@MainActor
struct StudyCalendarViewModelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = 2
        return calendar
    }

    private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func ics(_ events: [(uid: String, title: String, start: String, end: String)]) -> Data {
        let body = events.map {
            "BEGIN:VEVENT\nUID:\($0.uid)\nDTSTART:\($0.start)\nDTEND:\($0.end)\nSUMMARY:\($0.title)\nEND:VEVENT"
        }.joined(separator: "\n")
        return Data("BEGIN:VCALENDAR\n\(body)\nEND:VCALENDAR".utf8)
    }

    private struct Setup {
        let viewModel: StudyCalendarViewModel
        let loader: StubFeedLoader
        let moduleRepository: SwiftDataModuleRepository
        let container: ModelContainer
    }

    private func makeSetup(now: Date) throws -> Setup {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let loader = StubFeedLoader()
        let moduleRepository = SwiftDataModuleRepository(context: context)
        let viewModel = StudyCalendarViewModel(
            repository: SwiftDataStudyCalendarRepository(context: context),
            moduleRepository: moduleRepository,
            feedLoader: loader,
            parser: ICalendarFeedParser(),
            calendar: calendar,
            settings: InMemoryStudyPreferences(),
            now: { now }
        )
        return Setup(viewModel: viewModel, loader: loader, moduleRepository: moduleRepository, container: container)
    }

    @Test func subscribingNormalizesTheAddressAndLoadsEvents() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }
        setup.loader.data = ics([
            ("a", "Analysis", "20261020T080000Z", "20261020T093000Z"),
            ("b", "Algebra", "20261021T080000Z", "20261021T093000Z")
        ])

        try await setup.viewModel.subscribe(to: "webcal://example.com/plan.ics")

        let source = try #require(setup.viewModel.sources.first)
        #expect(source.kind == .subscription)
        #expect(source.url?.absoluteString == "https://example.com/plan.ics")
        #expect(setup.viewModel.events.count == 2)
    }

    @Test func invalidAddressIsRejected() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }

        await #expect(throws: StudyCalendarError.invalidSubscriptionURL) {
            try await setup.viewModel.subscribe(to: "ftp://example.com/plan.ics")
        }
        #expect(setup.viewModel.sources.isEmpty)
    }

    @Test func refreshDropsEventsThatLeftTheFeed() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }
        setup.loader.data = ics([
            ("a", "Analysis", "20261020T080000Z", "20261020T093000Z"),
            ("b", "Algebra", "20261021T080000Z", "20261021T093000Z")
        ])
        try await setup.viewModel.subscribe(to: "https://example.com/plan.ics")

        setup.loader.data = ics([("a", "Analysis", "20261020T080000Z", "20261020T093000Z")])
        let source = try #require(setup.viewModel.sources.first)
        await setup.viewModel.refresh(source)

        #expect(setup.viewModel.events.map(\.title) == ["Analysis"])
    }

    @Test func multiDayEventAppearsOnEveryDay() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }
        setup.loader.data = ics([("night", "Lange Nacht", "20261020T220000Z", "20261021T020000Z")])
        try await setup.viewModel.subscribe(to: "https://example.com/plan.ics")

        #expect(setup.viewModel.events(on: utc(2026, 10, 20)).count == 1)
        #expect(setup.viewModel.events(on: utc(2026, 10, 21)).count == 1)
        #expect(setup.viewModel.events(on: utc(2026, 10, 22)).isEmpty)
    }

    @Test func selectingADayInAnotherMonthSwitchesMonth() throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }

        #expect(setup.viewModel.selectedDate == utc(2026, 10, 16, 0))
        #expect(setup.viewModel.displayedMonth == utc(2026, 10, 1, 0))

        setup.viewModel.select(utc(2026, 11, 2))
        #expect(setup.viewModel.displayedMonth == utc(2026, 11, 1, 0))
        #expect(setup.viewModel.selectedDate == utc(2026, 11, 2, 0))
    }

    @Test func pagingMonthsKeepsTheDayAndClampsAtMonthEnd() throws {
        let setup = try makeSetup(now: utc(2027, 1, 31))
        defer { withExtendedLifetime(setup.container) {} }

        setup.viewModel.showMonth(offset: 1)

        #expect(setup.viewModel.displayedMonth == utc(2027, 2, 1, 0))
        #expect(setup.viewModel.selectedDate == utc(2027, 2, 28, 0))
    }

    @Test func movingSelectionByDaysFollowsIntoNextMonth() throws {
        let setup = try makeSetup(now: utc(2026, 10, 31))
        defer { withExtendedLifetime(setup.container) {} }

        setup.viewModel.moveSelection(byDays: 1)

        #expect(setup.viewModel.selectedDate == utc(2026, 11, 1, 0))
        #expect(setup.viewModel.displayedMonth == utc(2026, 11, 1, 0))
    }

    @Test func linkedModuleIsSearchableAndListedAsUpcoming() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }
        let module = StudyModule(id: UUID(), name: "Analysis I", code: "MAT101", color: .blue, createdAt: Date())
        try setup.moduleRepository.add(module)
        setup.loader.data = ics([("a", "Übung 3", "20261020T080000Z", "20261020T093000Z")])
        try await setup.viewModel.subscribe(to: "https://example.com/plan.ics")

        #expect(setup.viewModel.searchResults.isEmpty)
        let event = try #require(setup.viewModel.events.first)
        setup.viewModel.link(event, to: module.id)

        setup.viewModel.searchText = "analysis"
        #expect(setup.viewModel.searchResults.map(\.title) == ["Übung 3"])
        #expect(setup.viewModel.upcomingEvents(forModule: module.id).map(\.title) == ["Übung 3"])
        // `event` ist der Stand vor dem Verknüpfen; die Zuordnung steckt im neu geladenen Termin.
        let linked = try #require(setup.viewModel.events.first { $0.id == event.id })
        #expect(setup.viewModel.module(for: linked)?.id == module.id)
    }

    @Test func revealClearsSearchAndShowsTheEventsMonth() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }
        setup.loader.data = ics([("a", "Klausur", "20261203T080000Z", "20261203T100000Z")])
        try await setup.viewModel.subscribe(to: "https://example.com/plan.ics")
        setup.viewModel.mode = .agenda
        setup.viewModel.searchText = "klausur"

        let event = try #require(setup.viewModel.events.first)
        setup.viewModel.reveal(event)

        #expect(setup.viewModel.searchText.isEmpty)
        #expect(setup.viewModel.mode == .month)
        #expect(setup.viewModel.displayedMonth == utc(2026, 12, 1, 0))
        #expect(setup.viewModel.selectedDate == utc(2026, 12, 3, 0))
    }

    // MARK: Stundenplan → Module

    @Test func subscribingToATimetableCreatesModulesAndLinksEveryOccurrence() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }
        setup.loader.data = Data("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:ana
        DTSTART:20261013T080000Z
        DTEND:20261013T093000Z
        RRULE:FREQ=WEEKLY;COUNT=6
        SUMMARY:Analysis I (Vorlesung)
        END:VEVENT
        BEGIN:VEVENT
        UID:ana-ue
        DTSTART:20261015T120000Z
        DTEND:20261015T133000Z
        RRULE:FREQ=WEEKLY;COUNT=6
        SUMMARY:Übung zu Analysis I
        END:VEVENT
        BEGIN:VEVENT
        UID:dentist
        DTSTART:20261021T070000Z
        DTEND:20261021T080000Z
        SUMMARY:Zahnarzt
        END:VEVENT
        END:VCALENDAR
        """.utf8)

        try await setup.viewModel.subscribe(to: "https://example.com/plan.ics")

        let modules = try setup.moduleRepository.all()
        #expect(modules.map(\.name) == ["Analysis I"])
        let module = try #require(modules.first)
        let linked = setup.viewModel.events.filter { $0.moduleID == module.id }
        #expect(linked.count == 12)
        #expect(setup.viewModel.events.first { $0.title == "Zahnarzt" }?.moduleID == nil)
    }

    @Test func currentLectureIsTheRunningLinkedEvent() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 20, 8))
        defer { withExtendedLifetime(setup.container) {} }
        // Anderer Name als die Termine, damit der automatische Abgleich nicht schon verknüpft.
        let module = StudyModule(id: UUID(), name: "Mathe 1", code: "", color: .blue, createdAt: Date())
        try setup.moduleRepository.add(module)
        setup.loader.data = ics([
            ("a", "Algebra", "20261020T074500Z", "20261020T091500Z"),
            ("b", "Algebra", "20261021T074500Z", "20261021T091500Z")
        ])
        try await setup.viewModel.subscribe(to: "https://example.com/plan.ics")
        #expect(setup.viewModel.currentLecture == nil)

        let event = try #require(setup.viewModel.events.first { $0.externalID == "a" })
        setup.viewModel.link(event, to: module.id, applyToSeries: true)

        #expect(setup.viewModel.events.allSatisfy { $0.moduleID == module.id })
        #expect(setup.viewModel.currentLecture?.externalID == "a")
        #expect(setup.viewModel.nextLecture?.externalID == "b")
        #expect(setup.viewModel.liveModuleID == module.id)
    }

    @Test func eventsNamedLikeAnExistingModuleAreLinkedAutomatically() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }
        let module = StudyModule(id: UUID(), name: "Algebra", code: "", color: .blue, createdAt: Date())
        try setup.moduleRepository.add(module)
        setup.loader.data = ics([("a", "Algebra - Tutorium", "20261020T074500Z", "20261020T091500Z")])

        try await setup.viewModel.subscribe(to: "https://example.com/plan.ics")

        #expect(setup.viewModel.events.first?.moduleID == module.id)
        #expect(try setup.moduleRepository.all().count == 1)
    }

    @Test func rejectedCoursesAreNotCreatedAgain() async throws {
        let setup = try makeSetup(now: utc(2026, 10, 16))
        defer { withExtendedLifetime(setup.container) {} }
        setup.loader.data = ics([
            ("a", "Physik (Vorlesung)", "20261020T080000Z", "20261020T093000Z")
        ])
        setup.viewModel.ignoreCourse(named: "Physik")
        try await setup.viewModel.subscribe(to: "https://example.com/plan.ics")

        #expect(try setup.moduleRepository.all().isEmpty)
        let candidate = try #require(setup.viewModel.moduleCandidates().first)
        #expect(candidate.name == "Physik")

        setup.viewModel.applyModuleCandidates([candidate], rejected: [])
        #expect(try setup.moduleRepository.all().map(\.name) == ["Physik"])
        #expect(!setup.viewModel.ignoredCourseKeys.contains(candidate.key))
    }
}
