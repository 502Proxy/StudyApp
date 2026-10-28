import SwiftUI

/// Settings window (⌘,): one toolbar tab per topic, so the window stays small however many
/// settings the app gains.
struct SettingsView: View {
    let settings: any StudySettingsStore
    let updater: AppUpdater
    let studIP: StudIPViewModel
    let backup: BackupViewModel
    let notifications: NotificationsViewModel

    @AppStorage(ViewPreferences.settingsPaneKey) private var selection = SettingsPane.general

    var body: some View {
        TabView(selection: $selection) {
            ForEach(SettingsPane.allCases) { pane in
                Tab(pane.title, systemImage: pane.systemImage, value: pane) {
                    content(for: pane)
                }
            }
        }
    }

    @ViewBuilder
    private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralSettingsPane(settings: settings)
        case .schedule:
            ScheduleSettingsPane(settings: settings)
        case .studIP:
            SettingsForm(pane: pane) { StudIPSettingsSection(viewModel: studIP) }
        case .notifications:
            SettingsForm(pane: pane) { NotificationSettingsSection(viewModel: notifications) }
        case .backup:
            SettingsForm(pane: pane) { BackupSettingsSection(viewModel: backup) }
        case .updates:
            UpdateSettingsPane(updater: updater)
        }
    }
}
