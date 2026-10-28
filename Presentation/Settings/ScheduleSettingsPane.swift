import SwiftUI

/// How StudyApp turns the timetable into modules and keeps subscribed calendars fresh.
struct ScheduleSettingsPane: View {
    let settings: any StudySettingsStore

    @State private var autoCreateModules = true
    @State private var autoRefreshCalendars = true
    @State private var ignoredCount = 0
    @State private var importsStudIPTimetable = false

    var body: some View {
        SettingsForm(pane: .schedule) {
            Section {
                Toggle("Module automatisch aus dem Kalender anlegen", isOn: $autoCreateModules)
                Toggle("Abonnierte Kalender automatisch aktualisieren (stündlich)", isOn: $autoRefreshCalendars)
                Toggle("Termine verknüpfter Stud.IP-Veranstaltungen übernehmen", isOn: $importsStudIPTimetable)
                    .help("Lädt die Termine beim Stud.IP-Abgleich in die Kalenderquelle „Stud.IP“. Hast du den Stud.IP-Kalender schon als Link abonniert, entferne das Abo, sonst erscheinen Termine doppelt.")
                Button("Abgelehnte Veranstaltungen wieder vorschlagen (\(ignoredCount))") {
                    settings.ignoredCourseKeys = []
                    ignoredCount = 0
                }
                .disabled(ignoredCount == 0)
            } header: {
                Text("Stundenplan")
            } footer: {
                Text("Wiederkehrende Lehrveranstaltungen (Vorlesung, Übung, Tutorium …) werden als Modul angelegt und alle ihre Termine verknüpft. Gelöschte Module werden nicht erneut erstellt.")
            }
        }
        .onAppear {
            autoCreateModules = settings.autoCreateModules
            autoRefreshCalendars = settings.autoRefreshCalendars
            ignoredCount = settings.ignoredCourseKeys.count
            importsStudIPTimetable = settings.importsStudIPTimetable
        }
        .onChange(of: autoCreateModules) { _, value in settings.autoCreateModules = value }
        .onChange(of: autoRefreshCalendars) { _, value in settings.autoRefreshCalendars = value }
        .onChange(of: importsStudIPTimetable) { _, value in settings.importsStudIPTimetable = value }
    }
}
