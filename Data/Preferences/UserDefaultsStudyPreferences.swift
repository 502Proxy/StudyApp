import Foundation

/// Speichert Einstellungen und Lesefortschritt in `UserDefaults`.
/// Die Schlüssel sind öffentlich, damit SwiftUI-Ansichten sie per `@AppStorage` beobachten können.
@MainActor
final class UserDefaultsStudyPreferences: StudySettingsStore, ReadingProgressStore {
    enum Key {
        static let autoCreateModules = "settings.autoCreateModules"
        static let autoOpenLecture = "settings.autoOpenLecture"
        static let autoRefreshCalendars = "settings.autoRefreshCalendars"
        static let lectureLeadMinutes = "settings.lectureLeadMinutes"
        static let ignoredCourseKeys = "moduleDetection.ignoredKeys"
        static let lastAutoOpenedLecture = "autopilot.lastHandledLecture"
        static let automaticBackups = "backup.automatic"
        static let canteenID = "mensa.canteenID"
        static let notificationSettings = "notifications.settings"
        static func lastPage(_ documentID: UUID) -> String { "reading.page.\(documentID.uuidString)" }
        static func lastDocument(_ moduleID: UUID) -> String { "reading.document.\(moduleID.uuidString)" }
    }

    static let defaultLeadMinutes = 10

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var autoCreateModules: Bool {
        get { bool(Key.autoCreateModules, default: true) }
        set { defaults.set(newValue, forKey: Key.autoCreateModules) }
    }

    var autoOpenLecture: Bool {
        get { bool(Key.autoOpenLecture, default: true) }
        set { defaults.set(newValue, forKey: Key.autoOpenLecture) }
    }

    var autoRefreshCalendars: Bool {
        get { bool(Key.autoRefreshCalendars, default: true) }
        set { defaults.set(newValue, forKey: Key.autoRefreshCalendars) }
    }

    var lectureLeadMinutes: Int {
        get { defaults.object(forKey: Key.lectureLeadMinutes) as? Int ?? Self.defaultLeadMinutes }
        set { defaults.set(newValue, forKey: Key.lectureLeadMinutes) }
    }

    var ignoredCourseKeys: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.ignoredCourseKeys) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Key.ignoredCourseKeys) }
    }

    var lastAutoOpenedLecture: String? {
        get { defaults.string(forKey: Key.lastAutoOpenedLecture) }
        set { defaults.set(newValue, forKey: Key.lastAutoOpenedLecture) }
    }

    var automaticBackups: Bool {
        get { bool(Key.automaticBackups, default: true) }
        set { defaults.set(newValue, forKey: Key.automaticBackups) }
    }

    var canteenID: Int? {
        get { defaults.object(forKey: Key.canteenID) as? Int }
        set { defaults.set(newValue, forKey: Key.canteenID) }
    }

    /// Stored as JSON; unreadable or missing data falls back to the defaults.
    var notificationSettings: NotificationSettings {
        get {
            defaults.data(forKey: Key.notificationSettings)
                .flatMap { try? JSONDecoder().decode(NotificationSettings.self, from: $0) } ?? NotificationSettings()
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.notificationSettings) }
    }

    func lastPage(for documentID: UUID) -> Int? {
        let page = defaults.integer(forKey: Key.lastPage(documentID))
        return page > 0 ? page : nil
    }

    func setLastPage(_ page: Int, for documentID: UUID) {
        defaults.set(page, forKey: Key.lastPage(documentID))
    }

    func lastOpenedDocument(inModule moduleID: UUID) -> UUID? {
        defaults.string(forKey: Key.lastDocument(moduleID)).flatMap(UUID.init(uuidString:))
    }

    func setLastOpenedDocument(_ documentID: UUID, inModule moduleID: UUID) {
        defaults.set(documentID.uuidString, forKey: Key.lastDocument(moduleID))
    }

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }
}
