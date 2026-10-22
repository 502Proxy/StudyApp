import Foundation
import UserNotifications

/// Schedules `StudyNotification`s with `UNUserNotificationCenter`.
final class UserNotificationScheduler: NotificationScheduling {
    /// `userInfo` keys that carry the `NotificationTarget` back when the user clicks a notification.
    nonisolated enum UserInfoKey {
        static let kind = "target"
        static let moduleID = "moduleID"
    }

    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    func authorization() async -> NotificationAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        guard await authorization() == .notDetermined else { return await authorization() }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        return granted ? .authorized : .denied
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func schedule(_ notifications: [StudyNotification]) async {
        for notification in notifications {
            // A failure for one request (e.g. a date that just passed) must not stop the others.
            try? await center.add(request(for: notification))
        }
    }

    func cancel(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func request(for notification: StudyNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = Self.userInfo(for: notification.target)
        let trigger = notification.fireDate.map { date in
            UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date),
                repeats: false
            )
        }
        return UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
    }

    nonisolated static func userInfo(for target: NotificationTarget) -> [String: String] {
        switch target {
        case .lecture(let moduleID): [UserInfoKey.kind: "lecture", UserInfoKey.moduleID: moduleID.uuidString]
        case .assignment(let moduleID): [UserInfoKey.kind: "assignment", UserInfoKey.moduleID: moduleID.uuidString]
        case .today: [UserInfoKey.kind: "today"]
        }
    }

    /// Reads the target back; called from the notification delegate outside the main actor.
    nonisolated static func target(from userInfo: [AnyHashable: Any]) -> NotificationTarget? {
        let moduleID = (userInfo[UserInfoKey.moduleID] as? String).flatMap(UUID.init(uuidString:))
        switch (userInfo[UserInfoKey.kind] as? String, moduleID) {
        case ("lecture", let id?): return .lecture(moduleID: id)
        case ("assignment", let id?): return .assignment(moduleID: id)
        case ("today", _): return .today
        default: return nil
        }
    }
}
