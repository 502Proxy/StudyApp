import Foundation

/// Port für Einstellungen, die das Verhalten der Abläufe steuern (Automatiken rund um den Stundenplan).
/// Die Implementierung liegt in der Data-Schicht; Tests nutzen einen In-Memory-Speicher.
@MainActor
protocol StudySettingsStore: AnyObject {
    /// Lehrveranstaltungen aus dem Kalender automatisch als Modul anlegen.
    var autoCreateModules: Bool { get set }
    /// Beim Öffnen der App die laufende Vorlesung anzeigen.
    var autoOpenLecture: Bool { get set }
    /// Abonnierte Kalender beim Start und danach stündlich aktualisieren.
    var autoRefreshCalendars: Bool { get set }
    /// So viele Minuten vor Beginn gilt eine Vorlesung bereits als „jetzt“.
    var lectureLeadMinutes: Int { get set }
    /// Veranstaltungen (`CourseTitle.key`), die nicht (wieder) automatisch als Modul entstehen sollen.
    var ignoredCourseKeys: Set<String> { get set }
    /// Zuletzt automatisch geöffnete Vorlesung, damit das nur einmal pro Termin passiert.
    var lastAutoOpenedLecture: String? { get set }
    /// Create a weekly backup in the app's backup folder.
    var automaticBackups: Bool { get set }
    var notificationSettings: NotificationSettings { get set }
    var studyTimerSettings: StudyTimerSettings { get set }
}

extension StudySettingsStore {
    var lectureLeadTime: TimeInterval { TimeInterval(max(0, lectureLeadMinutes)) * 60 }
}

/// Port für den Lesefortschritt: letzte Seite pro Foliensatz, zuletzt gelesener Foliensatz pro Modul.
@MainActor
protocol ReadingProgressStore: AnyObject {
    func lastPage(for documentID: UUID) -> Int?
    func setLastPage(_ page: Int, for documentID: UUID)
    func lastOpenedDocument(inModule moduleID: UUID) -> UUID?
    func setLastOpenedDocument(_ documentID: UUID, inModule moduleID: UUID)
}

/// Flüchtige Implementierung beider Ports, z. B. für Tests und Previews.
@MainActor
final class InMemoryStudyPreferences: StudySettingsStore, ReadingProgressStore {
    var autoCreateModules = true
    var autoOpenLecture = true
    var autoRefreshCalendars = true
    var lectureLeadMinutes = 10
    var ignoredCourseKeys: Set<String> = []
    var lastAutoOpenedLecture: String?
    var automaticBackups = true
    var notificationSettings = NotificationSettings()
    var studyTimerSettings = StudyTimerSettings()
    private var pages: [UUID: Int] = [:]
    private var documents: [UUID: UUID] = [:]

    init() {}

    func lastPage(for documentID: UUID) -> Int? { pages[documentID] }
    func setLastPage(_ page: Int, for documentID: UUID) { pages[documentID] = page }
    func lastOpenedDocument(inModule moduleID: UUID) -> UUID? { documents[moduleID] }
    func setLastOpenedDocument(_ documentID: UUID, inModule moduleID: UUID) { documents[moduleID] = documentID }
}
