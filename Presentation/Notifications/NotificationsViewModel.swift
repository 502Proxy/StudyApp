import Foundation
import Observation

/// Keeps the system's scheduled notifications in line with the settings and the user's data.
@MainActor
@Observable
final class NotificationsViewModel {
    private(set) var authorization: NotificationAuthorization = .notDetermined

    var settings: NotificationSettings {
        didSet {
            guard settings != oldValue else { return }
            store.notificationSettings = settings
            Task { await settingsChanged() }
        }
    }

    private let scheduler: any NotificationScheduling
    private let syncNotifications: SyncNotificationsUseCase
    private let store: any StudySettingsStore
    private let now: () -> Date

    init(
        scheduler: any NotificationScheduling,
        modules: any ModuleRepository,
        calendar: any StudyCalendarRepository,
        assignments: any AssignmentRepository,
        store: any StudySettingsStore,
        now: @escaping () -> Date = { .now }
    ) {
        self.scheduler = scheduler
        self.store = store
        self.now = now
        syncNotifications = SyncNotificationsUseCase(
            scheduler: scheduler, modules: modules, calendar: calendar, assignments: assignments
        )
        settings = store.notificationSettings
    }

    /// Plans the notifications again; runs on launch and periodically. Never shows the permission prompt.
    func refresh() async {
        authorization = await scheduler.authorization()
        guard authorization == .authorized else { return }
        try? await syncNotifications(settings: settings, now: now())
    }

    /// Delivers notifications about files and announcements a background Stud.IP sync brought in.
    func notifyAfterSync(_ summary: StudIPSyncSummary) async {
        guard authorization == .authorized else { return }
        let notifications = [
            NotificationPlanner.newFiles(summary, settings: settings),
            NotificationPlanner.newAnnouncements(summary, settings: settings),
        ].compactMap { $0 }
        guard !notifications.isEmpty else { return }
        await scheduler.schedule(notifications)
    }

    /// Turning a kind on is the moment to ask for permission.
    private func settingsChanged() async {
        if settings.isAnyEnabled, await scheduler.authorization() == .notDetermined {
            authorization = await scheduler.requestAuthorization()
        }
        await refresh()
    }
}
