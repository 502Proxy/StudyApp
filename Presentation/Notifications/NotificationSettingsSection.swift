import AppKit
import SwiftUI

/// Notification options in the settings window.
struct NotificationSettingsSection: View {
    @Bindable var viewModel: NotificationsViewModel

    var body: some View {
        Section {
            Toggle("Vor Vorlesungen erinnern", isOn: $viewModel.settings.lectures)
            Stepper(value: $viewModel.settings.lectureLeadMinutes, in: NotificationSettings.leadMinuteRange, step: 5) {
                LabeledContent("Vorlauf", value: viewModel.settings.lectureLeadMinutes == 0 ? "zu Beginn" : "\(viewModel.settings.lectureLeadMinutes) Min.")
            }
            .disabled(!viewModel.settings.lectures)
            Toggle("An Abgaben erinnern (am Vortag und 3 Stunden vorher)", isOn: $viewModel.settings.assignments)
            Toggle("Neue Dateien aus Stud.IP melden", isOn: $viewModel.settings.newFiles)
            Toggle("Neue Ankündigungen aus Stud.IP melden", isOn: $viewModel.settings.announcements)
            if viewModel.authorization == .denied && viewModel.settings.isAnyEnabled {
                HStack {
                    Label("Mitteilungen sind in den Systemeinstellungen ausgeschaltet.", systemImage: "bell.slash")
                        .foregroundStyle(Theme.warning)
                    Spacer()
                    Button("Öffnen …") { Self.openSystemSettings() }
                }
            }
        } header: {
            Text("Mitteilungen")
        } footer: {
            Text("Ein Klick auf eine Erinnerung öffnet direkt die Folien bzw. die Aufgaben des Moduls.")
        }
        .task { await viewModel.refresh() }
    }

    private static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}
