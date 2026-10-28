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
