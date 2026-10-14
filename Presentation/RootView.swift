import SwiftUI

struct RootView: View {
    @Bindable var viewModel: ModulesViewModel
    let makeSlidesViewModel: SlidesViewModelFactory
    let makeLearningViewModel: LearningViewModelFactory

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            if let module = viewModel.selectedModule {
                ModuleDetailView(
                    module: module,
                    makeSlidesViewModel: makeSlidesViewModel,
                    makeLearningViewModel: makeLearningViewModel
                )
                    // Eigener Zustand pro Modul: Tab, geöffnetes PDF und Liste werden beim Wechsel zurückgesetzt.
                    .id(module.id)
            } else {
                ContentUnavailableView(
                    "Kein Modul ausgewählt",
                    systemImage: "sidebar.left",
                    description: Text("Wähle links ein Modul oder lege ein neues an.")
                )
                .background(Theme.background)
            }
        }
        .sheet(item: $viewModel.editorMode) { mode in
            ModuleEditorSheet(mode: mode) { draft in
                viewModel.save(draft)
            }
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
