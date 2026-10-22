import SwiftUI

extension View {
    /// Asks before a restore replaces all data; shown wherever `pendingRestore` is set.
    func backupRestoreConfirmation(_ viewModel: BackupViewModel) -> some View {
        modifier(BackupRestoreConfirmation(viewModel: viewModel))
    }
}

private struct BackupRestoreConfirmation: ViewModifier {
    @Bindable var viewModel: BackupViewModel

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Backup wiederherstellen?",
            isPresented: Binding(
                get: { viewModel.pendingRestore != nil },
                set: { if !$0 { viewModel.pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Alle Daten ersetzen", role: .destructive) {
                Task { await viewModel.confirmRestore() }
            }
        } message: {
            Text("„\(viewModel.pendingRestore?.lastPathComponent ?? "")“ ersetzt alle Module, Notizen und Folien. Der aktuelle Stand wird vorher automatisch gesichert.")
        }
    }
}
