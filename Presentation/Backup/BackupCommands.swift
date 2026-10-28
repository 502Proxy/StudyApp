import SwiftUI

/// „Backup erstellen …“ and „Backup wiederherstellen …“ in the File menu.
struct BackupCommands: Commands {
    let viewModel: BackupViewModel

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Divider()
            Button("Backup erstellen …") {
                BackupPanels.chooseDestination(suggestedName: viewModel.suggestedFileName) { url in
                    Task { await viewModel.create(at: url) }
                }
            }
            .disabled(viewModel.isWorking)
            Button("Backup wiederherstellen …") {
                BackupPanels.chooseBackup { url in viewModel.pendingRestore = url }
            }
            .disabled(viewModel.isWorking)
        }
    }
}
