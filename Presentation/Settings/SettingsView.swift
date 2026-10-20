import SwiftUI

/// Einstellungen (⌘,): Erscheinungsbild, Notizschrift und die Automatiken rund um den Stundenplan.
struct SettingsView: View {
    let settings: any StudySettingsStore
    let updater: AppUpdater

    @AppStorage(ViewPreferences.appearanceKey) private var appearance = AppAppearance.light
    @AppStorage(ViewPreferences.noteFontSizeKey) private var noteFontSize = NoteFontSize.standard
    @State private var autoCreateModules = true
    @State private var autoOpenLecture = true
    @State private var leadMinutes = 10
    @State private var autoRefreshCalendars = true
    @State private var ignoredCount = 0
    @State private var checksForUpdates = false
    @State private var downloadsUpdates = false

    var body: some View {
        Form {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Schriftgröße der Notizen") {
                    HStack(spacing: 10) {
                        Slider(value: $noteFontSize, in: NoteFontSize.range, step: NoteFontSize.step)
                            .frame(width: 180)
                        Text("\(Int(noteFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section {
                Toggle("Module automatisch aus dem Kalender anlegen", isOn: $autoCreateModules)
                Toggle("Abonnierte Kalender beim Start aktualisieren", isOn: $autoRefreshCalendars)
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

            Section {
                LabeledContent("Installiert", value: AppUpdater.versionText())
                if updater.isAvailable {
                    Toggle("Automatisch nach Updates suchen", isOn: $checksForUpdates)
                    Toggle("Updates im Hintergrund laden und installieren", isOn: $downloadsUpdates)
                        .disabled(!checksForUpdates)
                    Button("Jetzt nach Updates suchen …") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            } header: {
                Text("Updates")
            } footer: {
                if !updater.isAvailable {
                    Text("Automatische Updates sind in dieser Version nicht eingerichtet.")
                }
            }

            Section {
                Toggle("Laufende Vorlesung beim Öffnen der App anzeigen", isOn: $autoOpenLecture)
                Stepper(value: $leadMinutes, in: 0...30, step: 5) {
                    LabeledContent("Schon vor Beginn öffnen", value: leadMinutes == 0 ? "ab Beginn" : "\(leadMinutes) Min.")
                }
                .disabled(!autoOpenLecture)
            } header: {
                Text("Vorlesung")
            } footer: {
                Text("Öffnest du StudyApp während einer Vorlesung, landest du direkt in den Folien des Moduls – an der Stelle, an der du zuletzt warst.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            autoCreateModules = settings.autoCreateModules
            autoOpenLecture = settings.autoOpenLecture
            leadMinutes = settings.lectureLeadMinutes
            autoRefreshCalendars = settings.autoRefreshCalendars
            ignoredCount = settings.ignoredCourseKeys.count
            checksForUpdates = updater.automaticallyChecksForUpdates
            downloadsUpdates = updater.automaticallyDownloadsUpdates
        }
        .onChange(of: checksForUpdates) { _, value in updater.automaticallyChecksForUpdates = value }
        .onChange(of: downloadsUpdates) { _, value in updater.automaticallyDownloadsUpdates = value }
        .onChange(of: autoCreateModules) { _, value in settings.autoCreateModules = value }
        .onChange(of: autoOpenLecture) { _, value in settings.autoOpenLecture = value }
        .onChange(of: leadMinutes) { _, value in settings.lectureLeadMinutes = value }
        .onChange(of: autoRefreshCalendars) { _, value in settings.autoRefreshCalendars = value }
    }
}
