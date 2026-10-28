import Foundation
import Testing
@testable import StudyApp

struct WidgetSnapshotTests {
    let now = Date(timeIntervalSince1970: 1_761_642_000)

    private func lecture(inMinutes minutes: Double) -> WidgetSnapshot.Lecture {
        let start = now.addingTimeInterval(minutes * 60)
        return WidgetSnapshot.Lecture(
            moduleID: UUID(), moduleName: "Analysis I", location: "HS 1", start: start, end: start.addingTimeInterval(5_400)
        )
    }

    @Test func lectureAtADateIsTheRunningOrNextOne() {
        let running = lecture(inMinutes: -30)
        let next = lecture(inMinutes: 120)
        let snapshot = WidgetSnapshot(lectures: [running, next])

        #expect(snapshot.lecture(at: now) == running)
        #expect(snapshot.lecture(at: now.addingTimeInterval(61 * 60)) == next)
        #expect(snapshot.changeDates(after: now) == [running.end, next.start, next.end])
    }

    @Test func storeWritesOnlyChangesAndReadsBack() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "widget-\(UUID().uuidString)/snapshot.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let snapshot = WidgetSnapshot(dueModules: [.init(moduleID: UUID(), moduleName: "Analysis I", count: 4)])

        #expect(try WidgetSnapshotStore.save(snapshot, to: url))
        #expect(try !WidgetSnapshotStore.save(snapshot, to: url))
        #expect(WidgetSnapshotStore.load(from: url)?.dueCards == 4)
    }

    @Test func linksRoundTrip() {
        let module = StudyAppLink.module(UUID(), section: "flashcards")
        #expect(StudyAppLink(url: module.url) == module)
        #expect(StudyAppLink(url: StudyAppLink.today.url) == .today)
        #expect(StudyAppLink(url: URL(string: "https://example.org")!) == nil)
        #expect(StudyAppLink(url: URL(string: "studyapp://module/kaputt/slides")!) == nil)
    }
}

@MainActor
struct WidgetSnapshotBuilderTests {
    let now = Date(timeIntervalSince1970: 1_761_642_000)

    @Test func keepsUpcomingLecturesOfActiveModulesAndSortsDueCards() {
        let analysis = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: now)
        let algebra = StudyModule(id: UUID(), name: "Lineare Algebra", code: "", color: .teal, createdAt: now)
        let archived = StudyModule(id: UUID(), name: "Alt", code: "", color: .red, createdAt: now, isArchived: true)
        func event(_ module: StudyModule?, inHours hours: Double) -> StudyCalendarEvent {
            let start = now.addingTimeInterval(hours * 3_600)
            return StudyCalendarEvent(
                id: UUID(), externalID: UUID().uuidString, sourceID: UUID(), title: "VL", details: "", location: "HS 1",
                startDate: start, endDate: start.addingTimeInterval(5_400), moduleID: module?.id
            )
        }

        let snapshot = WidgetSnapshotBuilder.snapshot(
            events: [event(analysis, inHours: -3), event(archived, inHours: 1), event(nil, inHours: 2), event(algebra, inHours: 4)],
            modules: [analysis, algebra, archived],
            dueCounts: [analysis.id: 3, algebra.id: 8, archived.id: 5],
            exams: [],
            now: now
        )

        #expect(snapshot.lectures.map(\.moduleName) == ["Lineare Algebra"])
        #expect(snapshot.dueModules.map(\.count) == [8, 3])
        #expect(snapshot.dueCards == 11)
    }
}

@MainActor
struct WidgetLinkNavigationTests {
    @Test func linksOpenTheModuleSection() throws {
        let name = "WidgetLinkNavigationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let navigation = AppNavigation(defaults: defaults)
        let module = UUID()

        navigation.open(StudyAppLink.module(module, section: "slides"))
        #expect(navigation.currentLocation == .module(module, section: .slides))
        #expect(navigation.pendingIntent == .resumeSlides)

        navigation.open(StudyAppLink.module(module, section: "unbekannt"))
        #expect(navigation.currentLocation == .module(module, section: .overview))

        navigation.open(StudyAppLink.today)
        #expect(navigation.currentLocation == .today)
    }
}
