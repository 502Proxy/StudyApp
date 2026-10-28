import Foundation
import SwiftData

/// A stored Stud.IP announcement with its read state.
@Model
final class AnnouncementRecord {
    /// Stud.IP news ID.
    @Attribute(.unique) var id: String
    var moduleID: UUID
    var title: String
    var body: String
    var publishedAt: Date
    var isRead: Bool

    init(_ announcement: CourseAnnouncement) {
        id = announcement.id
        moduleID = announcement.moduleID
        title = announcement.title
        body = announcement.body
        publishedAt = announcement.publishedAt
        isRead = announcement.isRead
    }

    func apply(_ announcement: CourseAnnouncement) {
        moduleID = announcement.moduleID
        title = announcement.title
        body = announcement.body
        publishedAt = announcement.publishedAt
        isRead = announcement.isRead
    }

    func toDomain() -> CourseAnnouncement {
        CourseAnnouncement(id: id, moduleID: moduleID, title: title, body: body, publishedAt: publishedAt, isRead: isRead)
    }
}
