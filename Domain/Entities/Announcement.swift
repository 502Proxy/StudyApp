import Foundation

/// An announcement („Ankündigung“) of a Stud.IP course, stored per module so it can be shown
/// offline and marked as read.
struct CourseAnnouncement: Identifiable, Hashable, Codable, Sendable {
    /// The Stud.IP news ID; stable across syncs.
    let id: String
    let moduleID: UUID
    var title: String
    /// Plain text; Stud.IP's HTML is reduced to text by the data layer.
    var body: String
    var publishedAt: Date
    var isRead: Bool
}

/// An announcement as delivered by Stud.IP, before it is assigned to a module.
struct StudIPAnnouncement: Hashable, Sendable {
    let id: String
    var title: String
    var body: String
    var publishedAt: Date
}

/// Result of an announcement sync.
struct AnnouncementSyncResult: Equatable, Sendable {
    /// Announcements that appeared since the last sync. The first sync of a module reports none, so
    /// linking a course does not flood the user with old announcements.
    var new: [CourseAnnouncement] = []
    /// Modules whose announcements could not be loaded; the others are still synced.
    var failures: [String] = []
}
