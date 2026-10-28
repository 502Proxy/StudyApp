import SwiftUI

/// Appearance, note font size and what happens when the app opens during a lecture.
struct GeneralSettingsPane: View {
    let settings: any StudySettingsStore

    @AppStorage(ViewPreferences.appearanceKey) private var appearance = AppAppearance.standard
    @AppStorage(ViewPreferences.noteFontSizeKey) private var noteFontSize = NoteFontSize.standard
    @AppStorage(ViewPreferences.showsMenuBarItemKey) private var showsMenuBarItem = true
    @State private var autoOpenLecture = true
    @State private var leadMinutes = 10

    var body: some View {
        SettingsForm(pane: .general) {
            Section("Darstellung") {
                Picker("Erscheinungsbild", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("In der Menüleiste anzeigen (laufende Vorlesung, fällige Karten)", isOn: $showsMenuBarItem)
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
        .onAppear {
            autoOpenLecture = settings.autoOpenLecture
            leadMinutes = settings.lectureLeadMinutes
        }
        .onChange(of: autoOpenLecture) { _, value in settings.autoOpenLecture = value }
        .onChange(of: leadMinutes) { _, value in settings.lectureLeadMinutes = value }
    }
}
