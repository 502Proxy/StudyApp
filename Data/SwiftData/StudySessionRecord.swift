import Foundation
import SwiftData

/// A completed focus phase of the study timer.
@Model
final class StudySessionRecord {
    @Attribute(.unique) var id: UUID
    var moduleID: UUID?
    var startedAt: Date
    var duration: TimeInterval

    init(_ session: StudySession) {
        id = session.id
        moduleID = session.moduleID
        startedAt = session.startedAt
        duration = session.duration
    }

    func toDomain() -> StudySession {
        StudySession(id: id, moduleID: moduleID, startedAt: startedAt, duration: duration)
    }
}
