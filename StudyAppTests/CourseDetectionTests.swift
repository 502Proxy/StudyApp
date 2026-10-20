import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
struct CourseTitleAnalyzerTests {
    @Test(arguments: [
        ("Analysis I (Vorlesung)", "Analysis I", CourseEventKind.lecture),
        ("Analysis I - Übung", "Analysis I", .exercise),
        ("Übung zu Analysis I", "Analysis I", .exercise),
        ("VL Analysis I", "Analysis I", .lecture),
        ("Tutorium: Lineare Algebra II", "Lineare Algebra II", .tutorial),
        ("Lineare Algebra II [V]", "Lineare Algebra II", .lecture),
        ("Seminar Software Engineering", "Software Engineering", .seminar),
        ("Grundlagen der BWL – Tutorium 4", "Grundlagen der BWL", .tutorial),
        ("Datenbanken (V+Ü)", "Datenbanken", .lecture),
        ("Physik II Gr. 2", "Physik II", .other),
    ])
    func extractsNameAndKind(title: String, name: String, kind: CourseEventKind) throws {
        let result = try #require(CourseTitleAnalyzer.analyze(title))
        #expect(result.name == name)
        #expect(result.kind == kind)
    }

    @Test func extractsCourseCodes() throws {
        #expect(CourseTitleAnalyzer.analyze("inf030 Programmierung, Vorlesung")?.code == "inf030")
        #expect(CourseTitleAnalyzer.analyze("Mathematik für Informatiker (MAT101)")?.code == "MAT101")
        #expect(CourseTitleAnalyzer.analyze("2.01.123 Theoretische Informatik - Ü")?.name == "Theoretische Informatik")
    }

    @Test func lectureAndExerciseShareTheirKey() {
        let lecture = CourseTitleAnalyzer.analyze("Analysis I (Vorlesung)")
        let exercise = CourseTitleAnalyzer.analyze("Übung zu Analysis I")
        let other = CourseTitleAnalyzer.analyze("Analysis II (Vorlesung)")
        #expect(lecture?.key == exercise?.key)
        #expect(lecture?.key != other?.key)
    }

    @Test func titlesThatAreOnlyAKindHaveNoCourse() {
        #expect(CourseTitleAnalyzer.analyze("Übung 3") == nil)
        #expect(CourseTitleAnalyzer.analyze("Vorlesung") == nil)
        #expect(CourseTitleAnalyzer.analyze("   ") == nil)
    }
}

@MainActor
struct ModuleDetectionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .distantPast
    }

    private func event(_ title: String, _ start: Date, module: UUID? = nil, allDay: Bool = false) -> StudyCalendarEvent {
        StudyCalendarEvent(
            id: UUID(), externalID: UUID().uuidString, sourceID: UUID(), title: title, details: "", location: "",
            startDate: start, endDate: start.addingTimeInterval(allDay ? 86_400 : 5_400), moduleID: module, isAllDay: allDay
        )
    }

    private var detect: DetectModuleCandidatesUseCase {
        var detect = DetectModuleCandidatesUseCase()
        detect.calendar = calendar
        return detect
    }

    @Test func groupsLectureExerciseAndTutorialIntoOneCandidate() throws {
        let events = [
            event("Analysis I (Vorlesung)", date(10, 13, 8)),
            event("Analysis I (Vorlesung)", date(10, 20, 8)),
            event("Übung zu Analysis I", date(10, 15, 12)),
            event("Mensa mit Lisa", date(10, 14, 12)),
            event("Zahnarzt", date(10, 17, 9)),
            event("Zahnarzt", date(11, 17, 9)),
            event("Ferien", date(10, 1, 0), allDay: true),
        ]
        let candidates = detect(events: events, modules: [], now: date(10, 19, 9))
        let analysis = try #require(candidates.first { $0.name == "Analysis I" })
        #expect(analysis.occurrenceCount == 3)
        #expect(analysis.kinds == [.lecture, .exercise])
        #expect(analysis.isLikelyCourse)
        #expect(analysis.isCurrent)
        #expect(candidates.first { $0.name == "Zahnarzt" }?.isLikelyCourse == false)
        #expect(candidates.first { $0.name == "Mensa mit Lisa" }?.isLikelyCourse == false)
        #expect(!candidates.contains { $0.name == "Ferien" })
    }

    @Test func weeklySeriesWithoutKeywordCountsAsCourse() throws {
        let events = (0..<4).map { week in event("Mathematik für Informatiker", date(10, 5 + 7 * week, 10)) }
        let candidate = try #require(detect(events: events, modules: [], now: date(10, 19, 9)).first)
        #expect(candidate.isLikelyCourse)
    }

    @Test func matchesExistingModulesByNameCodeAndLinks() throws {
        let byName = StudyModule(id: UUID(), name: "Lineare Algebra II", code: "", color: .blue, createdAt: Date())
        let byCode = StudyModule(id: UUID(), name: "Programmieren", code: "inf030", color: .green, createdAt: Date())
        let byLink = StudyModule(id: UUID(), name: "Physik", code: "", color: .red, createdAt: Date())
        let events = [
            event("Tutorium: Lineare Algebra II", date(10, 16, 10)),
            event("inf030 Programmierung (Übung)", date(10, 16, 12)),
            event("Experimentalphysik (V)", date(10, 16, 14), module: byLink.id),
            event("Experimentalphysik (V)", date(10, 23, 14)),
        ]
        let candidates = detect(events: events, modules: [byName, byCode, byLink], now: date(10, 19, 9))
        #expect(candidates.first { $0.name == "Lineare Algebra II" }?.existingModuleID == byName.id)
        #expect(candidates.first { $0.name == "Programmierung" }?.existingModuleID == byCode.id)
        let physics = try #require(candidates.first { $0.name == "Experimentalphysik" })
        #expect(physics.existingModuleID == byLink.id)
        #expect(physics.unlinkedEventIDs.count == 1)
    }

    @Test func oldSemestersAreNotCurrent() throws {
        let events = [event("Altes Fach (VL)", date(1, 10, 8)), event("Altes Fach (VL)", date(1, 17, 8))]
        let candidate = try #require(detect(events: events, modules: [], now: date(10, 19, 9)).first)
        #expect(!candidate.isCurrent)
    }

    @Test func applyingCreatesModulesWithDistinctColorsAndKeepsManualLinks() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let context = container.mainContext
            let modules = SwiftDataModuleRepository(context: context)
            let calendarRepository = SwiftDataStudyCalendarRepository(context: context)
            let source = CalendarSource(id: UUID(), name: "Plan", url: nil, lastSyncedAt: nil, kind: .file)
            try calendarRepository.save(source: source)
            let manual = StudyModule(id: UUID(), name: "Eigenes Modul", code: "", color: .violet, createdAt: Date())
            try modules.add(manual)

            var events = [
                event("Analysis I (Vorlesung)", date(10, 13, 8)),
                event("Analysis I (Vorlesung)", date(10, 20, 8), module: manual.id),
                event("Physik (Vorlesung)", date(10, 14, 8)),
            ]
            events = events.map { var copy = $0; copy.sourceID = source.id; return copy }
            try calendarRepository.replaceEvents(forSource: source.id, with: events)

            let sync = SyncModulesWithCalendarUseCase(
                moduleRepository: modules,
                calendarRepository: calendarRepository,
                detect: detect,
                now: { date(10, 19, 9) }
            )
            let result = try sync(ignoredKeys: [CourseTitleAnalyzer.makeKey("Physik")])

            // „Analysis I“ ist über die manuelle Verknüpfung bereits „Eigenes Modul“ zugeordnet.
            #expect(result.createdModules.isEmpty)
            let stored = try calendarRepository.events()
            #expect(stored.filter { $0.title.hasPrefix("Analysis") }.allSatisfy { $0.moduleID == manual.id })
            #expect(stored.first { $0.title.hasPrefix("Physik") }?.moduleID == nil)

            let second = try sync(ignoredKeys: [])
            #expect(second.createdModules.map(\.name) == ["Physik"])
            #expect(second.createdModules.first?.color != manual.color)
        }
    }

    @Test func nextColorPrefersUnusedColors() {
        let modules = ModuleColor.allCases.dropLast().map {
            StudyModule(id: UUID(), name: $0.rawValue, code: "", color: $0, createdAt: Date())
        }
        #expect(ApplyModuleCandidatesUseCase.nextColor(for: modules) == ModuleColor.allCases.last)
    }
}

@MainActor
struct LectureScheduleTests {
    private let module = UUID()

    private func event(start: TimeInterval, end: TimeInterval, linked: Bool = true) -> StudyCalendarEvent {
        StudyCalendarEvent(
            id: UUID(), externalID: UUID().uuidString, sourceID: UUID(), title: "VL", details: "", location: "",
            startDate: Date(timeIntervalSince1970: start), endDate: Date(timeIntervalSince1970: end),
            moduleID: linked ? module : nil
        )
    }

    @Test func runningLinkedEventIsCurrent() {
        let running = event(start: 1_000, end: 6_400)
        let unlinked = event(start: 1_000, end: 6_400, linked: false)
        #expect(LectureSchedule.current(in: [unlinked, running], at: Date(timeIntervalSince1970: 2_000))?.id == running.id)
    }

    @Test func lectureCountsAsCurrentShortlyBeforeItStarts() {
        let soon = event(start: 10_000, end: 15_400)
        let now = Date(timeIntervalSince1970: 10_000 - 5 * 60)
        #expect(LectureSchedule.current(in: [soon], at: now, leadTime: 10 * 60)?.id == soon.id)
        #expect(LectureSchedule.current(in: [soon], at: now, leadTime: 0) == nil)
    }

    @Test func laterStartWinsWhenEventsOverlap() {
        let long = event(start: 0, end: 20_000)
        let short = event(start: 5_000, end: 9_000)
        #expect(LectureSchedule.current(in: [long, short], at: Date(timeIntervalSince1970: 6_000))?.id == short.id)
    }

    @Test func endedEventIsNotCurrentAndNextIsTheEarliestUpcoming() {
        let past = event(start: 0, end: 1_000)
        let later = event(start: 9_000, end: 10_000)
        let soon = event(start: 5_000, end: 6_000)
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(LectureSchedule.current(in: [past], at: now) == nil)
        #expect(LectureSchedule.next(in: [later, soon, past], after: now)?.id == soon.id)
    }
}
