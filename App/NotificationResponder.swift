import Foundation
import UserNotifications

/// Receives clicks on StudyApp notifications and shows banners while the app is in front.
/// Must be installed before the app finishes launching so clicks that launch the app are not lost.
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    /// Called on the main actor with the target of a clicked notification.
    var onOpen: (@MainActor (NotificationTarget) -> Void)?

    func install(on center: UNUserNotificationCenter = .current()) {
        center.delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let target = UserNotificationScheduler.target(from: response.notification.request.content.userInfo) else { return }
        await MainActor.run { self.onOpen?(target) }
    }
}
