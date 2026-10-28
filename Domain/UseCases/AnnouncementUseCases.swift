import Foundation

/// Loads the announcements of all linked, active modules and stores them.
///
/// Known announcements keep their read state; changed titles or texts are updated. Announcements older
/// than `maximumAge` are ignored, and those of unlinked or deleted modules are removed.
@MainActor
struct SyncAnnouncementsUseCase {
    static let maximumAge: TimeInterval = 60 * 86_400

    let service: any StudIPAnnouncementService
    let repository: any AnnouncementRepository
    var now: () -> Date = { .now }

    func callAsFunction(modules: [StudyModule], credentials: StudIPCredentials) async throws -> AnnouncementSyncResult {
        let linked = modules.filter { $0.studIPCourseID != nil && !$0.isArchived }
        try repository.deleteAll(exceptModules: Set(linked.map(\.id)))

        let oldest = now().addingTimeInterval(-Self.maximumAge)
        var result = AnnouncementSyncResult()
        for module in linked {
            guard let courseID = module.studIPCourseID else { continue }
            let loaded: [StudIPAnnouncement]
            do {
                loaded = try await service.announcements(inCourse: courseID, credentials)
            } catch StudIPError.sessionExpired {
                throw StudIPError.sessionExpired
            } catch {
                result.failures.append("\(module.name): \(error.localizedDescription)")
                continue
            }
            let stored = try repository.announcements(forModule: module.id)
            let known = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
            let merged = loaded
                .filter { $0.publishedAt >= oldest }
                .map { announcement in
                    CourseAnnouncement(
                        id: announcement.id,
                        moduleID: module.id,
                        title: announcement.title,
                        body: announcement.body,
                        publishedAt: announcement.publishedAt,
                        isRead: known[announcement.id]?.isRead ?? false
                    )
                }
            try repository.upsert(merged)
            if !stored.isEmpty {
                result.new += merged.filter { known[$0.id] == nil }
            }
        }
        result.new.sort { $0.publishedAt > $1.publishedAt }
        return result
    }
}
