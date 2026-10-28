import SwiftUI

/// Installed version and Sparkle's update options.
struct UpdateSettingsPane: View {
    let updater: AppUpdater

    @State private var checksForUpdates = false
    @State private var downloadsUpdates = false

    var body: some View {
        SettingsForm(pane: .updates) {
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
        }
        .onAppear {
            checksForUpdates = updater.automaticallyChecksForUpdates
            downloadsUpdates = updater.automaticallyDownloadsUpdates
        }
        .onChange(of: checksForUpdates) { _, value in updater.automaticallyChecksForUpdates = value }
        .onChange(of: downloadsUpdates) { _, value in updater.automaticallyDownloadsUpdates = value }
    }
}
