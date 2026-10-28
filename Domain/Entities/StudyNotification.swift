import Foundation

/// Whether the system lets StudyApp show notifications.
enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
}

/// What opening a notification should show.
nonisolated enum NotificationTarget: Equatable, Sendable {
    /// The slides of a module's lecture.
    case lecture(moduleID: UUID)
    /// The assignments of a module.
    case assignment(moduleID: UUID)
    /// The start page, e.g. after new Stud.IP files arrived for several modules.
    case today
}

/// A local notification StudyApp wants the system to deliver.
struct StudyNotification: Equatable, Sendable {
    /// Stable identifier, so planning again replaces instead of duplicating a notification.
    let id: String
    let title: String
    let body: String
    /// `nil` delivers immediately.
    let fireDate: Date?
    let target: NotificationTarget

    /// Every identifier StudyApp schedules starts with this prefix, so foreign requests are never touched.
    static let identifierPrefix = "studyapp."
    /// The study timer's „phase is over“ notification. Not part of the plan, so the plan sync keeps it.
    static let studyTimerIdentifier = "studyapp.timer"
}

/// Which notifications the user wants. Stored as one value so new options do not need new storage keys.
/// Everything is off by default: permission is only requested once the user turns a kind on.
struct NotificationSettings: Codable, Equatable, Sendable {
    var lectures = false
    /// Minutes before a lecture starts.
    var lectureLeadMinutes = 10
    var assignments = false
    var newFiles = false

    static let leadMinuteRange = 0...60

    var isAnyEnabled: Bool { lectures || assignments || newFiles }
}
