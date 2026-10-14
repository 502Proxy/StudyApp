import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: ModulesViewModel
    @State private var pendingDeletion: StudyModule?

    var body: some View {
        List(selection: $viewModel.selectedID) {
            Section("Module") {
                ForEach(viewModel.modules) { module in
                    ModuleRow(module: module)
                        .tag(module.id)
                        .contextMenu {
                            Button("Bearbeiten") {
                                viewModel.editorMode = .edit(module)
                            }
                            Divider()
                            Button("Löschen", role: .destructive) {
                                pendingDeletion = module
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if viewModel.modules.isEmpty {
                ContentUnavailableView(
                    "Noch keine Module",
                    systemImage: "books.vertical",
                    description: Text("Lege mit + dein erstes Modul an.")
                )
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.editorMode = .create
                } label: {
                    Label("Neues Modul", systemImage: "plus")
                }
            }
        }
        .onDeleteCommand {
            pendingDeletion = viewModel.selectedModule
        }
        .confirmationDialog(
            "Modul löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { module in
            Button("„\(module.name)“ löschen", role: .destructive) {
                viewModel.delete(module)
            }
        } message: { _ in
            Text("Das Modul wird entfernt.")
        }
    }
}

private struct ModuleRow: View {
    let module: StudyModule

    var body: some View {
        HStack(spacing: 10) {
            ColorDot(color: module.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                if !module.code.isEmpty {
                    Text(module.code)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
