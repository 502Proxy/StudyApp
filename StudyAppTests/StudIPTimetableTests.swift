import Foundation
import Testing
@testable import StudyApp

@MainActor
final class FakeScheduleService: StudIPScheduleService {
    var byCourse: [String: [StudIPCourseDate]] = [:]
    var failingCourses: [String: StudIPError] = [:]

    func courseDates(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPCourseDate] {
        if let error = failingCourses[courseID] { throw error }
        return byCourse[courseID] ?? []
    }
}

@MainActor
struct SyncStudIPTimetableTests {
    let service = FakeScheduleService()
    let repository = InMemoryCalendarRepository()
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let credentials = StudIPCredentials(
        account: StudIPAccount(serverURL: URL(string: "https://elearning.uni-oldenburg.de")!, username: "abcd1234"),
        password: "geheim"
    )

    private var sync: SyncStudIPTimetableUseCase {
        SyncStudIPTimetableUseCase(service: service, repository: repository, now: { [now] in now })
    }

    private func module(_ name: String, course: String?) -> StudyModule {
        StudyModule(id: UUID(), name: name, code: "", color: .blue, createdAt: now, studIPCourseID: course)
    }

    private func date(_ id: String, inDays days: Double, title: String = "Vorlesung", cancelled: Bool = false) -> StudIPCourseDate {
        let start = now.addingTimeInterval(days * 86_400)
        return StudIPCourseDate(
            id: id, title: title, details: "", location: "HS 1",
            start: start, end: start.addingTimeInterval(5_400), isCancelled: cancelled
        )
    }

    @Test func importsDatesIntoOneLinkedSource() async throws {
        let analysis = module("Analysis I", course: "c1")
        service.byCourse["c1"] = [date("d1", inDays: 1), date("d2", inDays: 8, title: "Analysis I")]

        try await sync(modules: [analysis], credentials: credentials)

        let source = try #require(repository.storedSources.first)
        #expect(source.kind == .studIP)
        #expect(source.name == "Stud.IP")
        let events = repository.storedEvents.sorted { $0.startDate < $1.startDate }
        #expect(events.map(\.title) == ["Analysis I – Vorlesung", "Analysis I"])
        #expect(events.allSatisfy { $0.moduleID == analysis.id && $0.location == "HS 1" })
    }

    @Test func refreshKeepsIDsAndRemovesDeletedDates() async throws {
        let analysis = module("Analysis I", course: "c1")
        service.byCourse["c1"] = [date("d1", inDays: 1), date("d2", inDays: 2)]
        try await sync(modules: [analysis], credentials: credentials)
        let firstID = try #require(repository.storedEvents.first { $0.externalID == "studip:d1" }?.id)

        service.byCourse["c1"] = [date("d1", inDays: 3)]
        try await sync(modules: [analysis], credentials: credentials)

        #expect(repository.storedSources.count == 1)
        #expect(repository.storedEvents.map(\.id) == [firstID])
    }

    @Test func marksCancelledDatesAndSkipsDatesOutsideTheWindow() async throws {
        let analysis = module("Analysis I", course: "c1")
        service.byCourse["c1"] = [date("old", inDays: -60), date("far", inDays: 400), date("off", inDays: 2, cancelled: true)]

        try await sync(modules: [analysis], credentials: credentials)

        #expect(repository.storedEvents.map(\.title) == ["Entfällt: Analysis I – Vorlesung"])
    }

    @Test func failingModuleKeepsItsStoredDates() async throws {
        let analysis = module("Analysis I", course: "c1")
        let algebra = module("Lineare Algebra", course: "c2")
        service.byCourse["c1"] = [date("a", inDays: 1)]
        service.byCourse["c2"] = [date("b", inDays: 1)]
        try await sync(modules: [analysis, algebra], credentials: credentials)

        service.failingCourses["c1"] = .notFound
        service.byCourse["c2"] = []
        let failures = try await sync(modules: [analysis, algebra], credentials: credentials)

        #expect(failures.count == 1)
        #expect(repository.storedEvents.map(\.externalID) == ["studip:a"])
    }

    @Test func createsNoSourceWithoutLinkedModules() async throws {
        try await sync(modules: [module("Ohne Kurs", course: nil)], credentials: credentials)
        #expect(repository.storedSources.isEmpty)
    }

    @Test func expiredSessionStopsTheSync() async throws {
        service.failingCourses["c1"] = .sessionExpired
        await #expect(throws: StudIPError.sessionExpired) {
            try await sync(modules: [module("Analysis I", course: "c1")], credentials: credentials)
        }
    }
}

struct StudIPCourseDateParsingTests {
    private func resource(_ attributes: [String: Any]) -> StudIPJSONAPIParser.Resource {
        ["type": "course-events", "id": "e1", "attributes": attributes]
    }

    @Test func readsTimesLocationAndCancellation() throws {
        let date = try #require(StudIPJSONAPIParser.courseDate(resource([
            "title": "Vorlesung",
            "description": "<p>Kapitel 3</p>",
            "start": "2026-10-28T10:15:00+01:00",
            "end": "2026-10-28T11:45:00+01:00",
            "location": "HS 1",
            "is-cancelled": true,
        ])))

        #expect(date.id == "e1")
        #expect(date.title == "Vorlesung")
        #expect(date.details == "Kapitel 3")
        #expect(date.location == "HS 1")
        #expect(date.isCancelled)
        #expect(date.end.timeIntervalSince(date.start) == 5_400)
    }

    @Test func acceptsOlderAttributeNamesAndSkipsDatesWithoutStart() {
        let date = StudIPJSONAPIParser.courseDate(resource(["categories": "Übung", "begin": 1_760_000_000, "room": "SR 3"]))
        #expect(date?.title == "Übung")
        #expect(date?.location == "SR 3")
        #expect(date?.end == date?.start)
        #expect(StudIPJSONAPIParser.courseDate(resource(["title": "ohne Zeit"])) == nil)
    }
}

@MainActor
struct StudIPTimetableSyncSettingTests {
    let service = FakeStudIPService()
    let schedule = FakeScheduleService()
    let store = InMemoryStudIPAccountStore()
    let modules = FakeModuleRepository()
    let slides = FakeSlideDocumentRepository()
    let calendar = InMemoryCalendarRepository()
    let settings = InMemoryStudyPreferences()

    private func makeViewModel() -> StudIPViewModel {
        StudIPViewModel(
            service: service,
            store: store,
            moduleRepository: modules,
            slideRepository: slides,
            importer: ImportSlideDocumentUseCase(repository: slides, storage: FakeFileStorage(), inspector: FakeInspector(pages: 3)),
            timetableSync: SyncStudIPTimetableUseCase(service: schedule, repository: calendar),
            settings: settings
        )
    }

    private func prepare() throws {
        try store.save(StudIPCredentials(
            account: StudIPAccount(serverURL: URL(string: "https://elearning.uni-oldenburg.de")!, username: "abcd1234"),
            password: "geheim"
        ))
        try modules.add(StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: .now, studIPCourseID: "c1"))
        let start = Date.now.addingTimeInterval(86_400)
        schedule.byCourse["c1"] = [
            StudIPCourseDate(id: "d1", title: "Vorlesung", details: "", location: "", start: start, end: start, isCancelled: false),
        ]
    }

    @Test func importsTheTimetableOnlyWhenTurnedOn() async throws {
        try prepare()
        let viewModel = makeViewModel()
        var reloads = 0
        viewModel.onTimetableSynced = { reloads += 1 }

        await viewModel.syncNow()
        #expect(calendar.storedEvents.isEmpty)

        settings.importsStudIPTimetable = true
        await viewModel.syncNow()
        #expect(calendar.storedEvents.map(\.externalID) == ["studip:d1"])
        #expect(reloads == 1)
    }
}
