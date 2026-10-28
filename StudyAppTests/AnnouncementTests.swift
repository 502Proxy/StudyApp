import Foundation
import Testing
@testable import StudyApp

@MainActor
final class FakeAnnouncementService: StudIPAnnouncementService {
    var byCourse: [String: [StudIPAnnouncement]] = [:]
    var failingCourses: [String: StudIPError] = [:]

    func announcements(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPAnnouncement] {
        if let error = failingCourses[courseID] { throw error }
        return byCourse[courseID] ?? []
    }
}

@MainActor
final class InMemoryAnnouncementRepository: AnnouncementRepository {
    private(set) var items: [String: CourseAnnouncement] = [:]

    func all() throws -> [CourseAnnouncement] {
        items.values.sorted { $0.publishedAt > $1.publishedAt }
    }

    func announcements(forModule moduleID: UUID) throws -> [CourseAnnouncement] {
        try all().filter { $0.moduleID == moduleID }
    }

    func upsert(_ announcements: [CourseAnnouncement]) throws {
        for announcement in announcements { items[announcement.id] = announcement }
    }

    func markRead(ids: Set<String>) throws {
        for id in ids { items[id]?.isRead = true }
    }

    func deleteAll(exceptModules moduleIDs: Set<UUID>) throws {
        items = items.filter { moduleIDs.contains($0.value.moduleID) }
    }
}

@MainActor
struct SyncAnnouncementsTests {
    let service = FakeAnnouncementService()
    let repository = InMemoryAnnouncementRepository()
    let now = Date(timeIntervalSince1970: 1_760_000_000)
    let credentials = StudIPCredentials(
        account: StudIPAccount(serverURL: URL(string: "https://elearning.uni-oldenburg.de")!, username: "abcd1234"),
        password: "geheim"
    )

    private var sync: SyncAnnouncementsUseCase {
        SyncAnnouncementsUseCase(service: service, repository: repository, now: { [now] in now })
    }

    private func module(_ name: String, course: String?, archived: Bool = false) -> StudyModule {
        var module = StudyModule(id: UUID(), name: name, code: "", color: .blue, createdAt: now)
        module.studIPCourseID = course
        module.isArchived = archived
        return module
    }

    private func news(_ id: String, daysAgo: Double, title: String = "Raumänderung") -> StudIPAnnouncement {
        StudIPAnnouncement(id: id, title: title, body: "Text", publishedAt: now.addingTimeInterval(-daysAgo * 86_400))
    }

    @Test func firstSyncStoresAnnouncementsWithoutReportingThemAsNew() async throws {
        let analysis = module("Analysis I", course: "c1")
        service.byCourse["c1"] = [news("n1", daysAgo: 1), news("n2", daysAgo: 3)]

        let result = try await sync(modules: [analysis], credentials: credentials)

        #expect(result.new.isEmpty)
        #expect(try repository.announcements(forModule: analysis.id).map(\.id) == ["n1", "n2"])
    }

    @Test func laterSyncReportsOnlyNewAnnouncementsAndKeepsReadState() async throws {
        let analysis = module("Analysis I", course: "c1")
        service.byCourse["c1"] = [news("n1", daysAgo: 2)]
        _ = try await sync(modules: [analysis], credentials: credentials)
        try repository.markRead(ids: ["n1"])

        service.byCourse["c1"] = [news("n2", daysAgo: 0), news("n1", daysAgo: 2, title: "Raumänderung (aktualisiert)")]
        let result = try await sync(modules: [analysis], credentials: credentials)

        #expect(result.new.map(\.id) == ["n2"])
        let stored = try repository.announcements(forModule: analysis.id)
        #expect(stored.first { $0.id == "n1" }?.isRead == true)
        #expect(stored.first { $0.id == "n1" }?.title == "Raumänderung (aktualisiert)")
        #expect(stored.first { $0.id == "n2" }?.isRead == false)
    }

    @Test func ignoresOldAnnouncementsAndUnlinkedOrArchivedModules() async throws {
        let linked = module("Analysis I", course: "c1")
        let archived = module("Altes Modul", course: "c2", archived: true)
        let unlinked = module("Ohne Kurs", course: nil)
        service.byCourse["c1"] = [news("old", daysAgo: 90), news("fresh", daysAgo: 1)]
        service.byCourse["c2"] = [news("archived", daysAgo: 1)]

        _ = try await sync(modules: [linked, archived, unlinked], credentials: credentials)

        #expect(try repository.all().map(\.id) == ["fresh"])
    }

    @Test func removesAnnouncementsOfModulesThatAreNoLongerLinked() async throws {
        var analysis = module("Analysis I", course: "c1")
        service.byCourse["c1"] = [news("n1", daysAgo: 1)]
        _ = try await sync(modules: [analysis], credentials: credentials)

        analysis.studIPCourseID = nil
        _ = try await sync(modules: [analysis], credentials: credentials)

        #expect(try repository.all().isEmpty)
    }

    @Test func failingCourseIsReportedAndOthersStillSync() async throws {
        let broken = module("Defekt", course: "c1")
        let fine = module("Analysis I", course: "c2")
        service.failingCourses["c1"] = .notFound
        service.byCourse["c2"] = [news("n1", daysAgo: 1)]

        let result = try await sync(modules: [broken, fine], credentials: credentials)

        #expect(result.failures.count == 1)
        #expect(try repository.all().map(\.id) == ["n1"])
    }

    @Test func expiredSessionStopsTheSync() async throws {
        service.failingCourses["c1"] = .sessionExpired
        await #expect(throws: StudIPError.sessionExpired) {
            try await sync(modules: [module("Analysis I", course: "c1")], credentials: credentials)
        }
    }
}

struct StudIPAnnouncementParsingTests {
    private func resource(_ attributes: [String: Any]) -> StudIPJSONAPIParser.Resource {
        ["type": "news", "id": "n1", "attributes": attributes]
    }

    @Test func readsTitleTextAndPublicationDate() throws {
        let announcement = try #require(StudIPJSONAPIParser.announcement(resource([
            "title": "Raumänderung",
            "content": "<p>Die Vorlesung findet in <strong>HS 2</strong> statt.</p><p>Bis dann &amp; viele Grüße</p>",
            "publication-start": "2026-10-20T08:00:00+02:00",
            "mkdate": "2026-10-19T12:00:00+02:00",
        ])))

        #expect(announcement.id == "n1")
        #expect(announcement.title == "Raumänderung")
        #expect(announcement.body == "Die Vorlesung findet in HS 2 statt.\nBis dann & viele Grüße")
        #expect(announcement.publishedAt == ISO8601DateFormatter().date(from: "2026-10-20T06:00:00Z"))
    }

    @Test func fallsBackToCreationDateAndSkipsIncompleteResources() {
        let fallback = StudIPJSONAPIParser.announcement(resource(["title": "Info", "mkdate": 1_760_000_000]))
        #expect(fallback?.publishedAt == Date(timeIntervalSince1970: 1_760_000_000))
        #expect(StudIPJSONAPIParser.announcement(resource(["content": "ohne Titel", "mkdate": 1]))?.id == nil)
        #expect(StudIPJSONAPIParser.announcement(resource(["title": "ohne Datum"])) == nil)
    }
}

@MainActor
struct AnnouncementNotificationTests {
    private func announcement(_ id: String, title: String) -> CourseAnnouncement {
        CourseAnnouncement(id: id, moduleID: UUID(), title: title, body: "Die Übung entfällt.", publishedAt: .now, isRead: false)
    }

    @Test func notifiesOnlyWhenTurnedOn() {
        let summary = StudIPSyncSummary(newAnnouncements: [announcement("n1", title: "Übung entfällt")])
        #expect(NotificationPlanner.newAnnouncements(summary, settings: NotificationSettings()) == nil)

        var settings = NotificationSettings()
        settings.announcements = true
        let single = NotificationPlanner.newAnnouncements(summary, settings: settings)
        #expect(single?.title == "Übung entfällt")
        #expect(single?.body == "Die Übung entfällt.")

        let several = StudIPSyncSummary(newAnnouncements: [announcement("n1", title: "A"), announcement("n2", title: "B")])
        #expect(NotificationPlanner.newAnnouncements(several, settings: settings)?.title == "2 neue Ankündigungen in Stud.IP")
    }

    @Test func settingsStoredBeforeAnnouncementsExistedStayReadable() throws {
        let old = Data(#"{"lectures":true,"lectureLeadMinutes":15,"assignments":false,"newFiles":true}"#.utf8)
        let settings = try JSONDecoder().decode(NotificationSettings.self, from: old)
        #expect(settings.lectures)
        #expect(settings.lectureLeadMinutes == 15)
        #expect(settings.newFiles)
        #expect(!settings.announcements)
    }

    @Test func syncSummaryMentionsNewAnnouncements() {
        let summary = StudIPSyncSummary(checkedModules: 1, newAnnouncements: [announcement("n1", title: "A")])
        #expect(StudIPViewModel.summaryText(summary) == "Stud.IP: 1 neue Ankündigung")
    }
}

@MainActor
struct AnnouncementsViewModelTests {
    let repository = InMemoryAnnouncementRepository()
    let modules = FakeModuleRepository()

    @Test func showsAnnouncementsOfExistingModulesAndMarksThemRead() throws {
        let module = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: .now)
        try modules.add(module)
        try repository.upsert([
            CourseAnnouncement(id: "a", moduleID: module.id, title: "A", body: "", publishedAt: .now, isRead: false),
            CourseAnnouncement(id: "orphan", moduleID: UUID(), title: "B", body: "", publishedAt: .now, isRead: false),
        ])
        let viewModel = AnnouncementsViewModel(repository: repository, modules: modules)

        viewModel.load()
        #expect(viewModel.items.map(\.id) == ["a"])
        #expect(viewModel.unread.count == 1)

        viewModel.open(try #require(viewModel.items.first))
        #expect(viewModel.selected?.id == "a")
        #expect(viewModel.unread.isEmpty)
    }
}
