import Foundation

/// Öffnet beim Start (oder beim Zurückkehren in die App) die Folien der Vorlesung, die gerade läuft.
///
/// Pro Termin passiert das beim Aktivieren der App nur einmal, damit man während der Vorlesung
/// frei in andere Bereiche wechseln kann, ohne ständig zurückgeholt zu werden. Ein Neustart
/// der App öffnet die laufende Vorlesung dagegen immer.
@MainActor
final class LectureAutopilot {
    private let navigation: AppNavigation
    private let calendar: StudyCalendarViewModel
    private let modules: ModulesViewModel
    private let settings: any StudySettingsStore

    init(navigation: AppNavigation, calendar: StudyCalendarViewModel, modules: ModulesViewModel, settings: any StudySettingsStore) {
        self.navigation = navigation
        self.calendar = calendar
        self.modules = modules
        self.settings = settings
    }

    /// - Parameter isLaunch: `true` beim App-Start, `false` beim erneuten Aktivieren.
    /// - Returns: Ob eine Vorlesung geöffnet wurde.
    @discardableResult
    func run(isLaunch: Bool) -> Bool {
        guard settings.autoOpenLecture else { return false }
        calendar.tick()
        guard let lecture = calendar.currentLecture,
              let moduleID = lecture.moduleID,
              let module = modules.module(withID: moduleID) else { return false }

        let key = "\(lecture.externalID)|\(lecture.startDate.timeIntervalSince1970)"
        if !isLaunch {
            guard settings.lastAutoOpenedLecture != key else { return false }
            // Wer schon im Modul ist, wird nicht umgeleitet.
            if navigation.selectedModuleID == moduleID {
                settings.lastAutoOpenedLecture = key
                return false
            }
        }
        settings.lastAutoOpenedLecture = key
        navigation.show(module: moduleID, section: .slides, intent: .resumeSlides)
        let state = lecture.startDate <= calendar.referenceDate ? "läuft gerade" : "beginnt gleich"
        calendar.notify("„\(module.name)“ \(state) – Folien geöffnet.")
        return true
    }
}
