import AppKit
import SwiftUI

/// Backup controls in the settings window.
struct BackupSettingsSection: View {
    @Bindable var viewModel: BackupViewModel
    /// Confirmed here rather than in the main window, which may be hidden behind the settings.
    @State private var restoreCandidate: URL?

    var body: some View {
        Section {
            Toggle(
                "Wöchentlich automatisch sichern (die letzten \(AutomaticBackupPolicy.retainedCount) bleiben)",
                isOn: $viewModel.automaticBackups
            )
            LabeledContent("Letztes Backup") {
                Text(viewModel.lastBackup.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "noch keins")
            }
            HStack {
                Button("Backup erstellen …") {
                    BackupPanels.chooseDestination(suggestedName: viewModel.suggestedFileName) { url in
                        Task { await viewModel.create(at: url) }
                    }
                }
                Button("Wiederherstellen …") {
                    BackupPanels.chooseBackup(in: viewModel.backupDirectory) { url in restoreCandidate = url }
                }
                if viewModel.isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Ordner zeigen") {
                    NSWorkspace.shared.activateFileViewerSelecting([viewModel.backupDirectory])
                }
            }
            .disabled(viewModel.isWorking)
        } header: {
            Text("Backup")
        } footer: {
            Text("Ein Backup enthält Module, Notizen, Karteikarten, Lernzettel, Aufgaben, Kalender und alle Folien mit Markierungen – aber keine Stud.IP-Zugangsdaten. Vor jeder Wiederherstellung sichert StudyApp den aktuellen Stand automatisch.")
        }
        .confirmationDialog(
            "Backup wiederherstellen?",
            isPresented: Binding(get: { restoreCandidate != nil }, set: { if !$0 { restoreCandidate = nil } }),
            titleVisibility: .visible,
            presenting: restoreCandidate
        ) { url in
            Button("Alle Daten ersetzen", role: .destructive) {
                Task { await viewModel.restore(from: url) }
            }
        } message: { url in
            Text("„\(url.lastPathComponent)“ ersetzt alle Module, Notizen und Folien. Der aktuelle Stand wird vorher automatisch gesichert.")
        }
    }
}
