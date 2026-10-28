import Foundation

/// Stores course announcements.
@MainActor
protocol AnnouncementRepository {
    /// All announcements, newest first.
    func all() throws -> [CourseAnnouncement]
    func announcements(forModule moduleID: UUID) throws -> [CourseAnnouncement]
    /// Inserts new announcements and replaces existing ones with the same ID.
    func upsert(_ announcements: [CourseAnnouncement]) throws
    func markRead(ids: Set<String>) throws
    /// Removes announcements of modules that no longer exist or are no longer linked.
    func deleteAll(exceptModules moduleIDs: Set<UUID>) throws
}

/// Port for reading announcements from Stud.IP. Kept apart from `StudIPService` so features depend
/// only on the requests they use.
@MainActor
protocol StudIPAnnouncementService {
    func announcements(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPAnnouncement]
}
