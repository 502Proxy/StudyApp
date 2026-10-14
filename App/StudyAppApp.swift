import SwiftUI

@main
struct StudyAppApp: App {
    private let container: AppContainer
    @State private var modulesViewModel: ModulesViewModel

    init() {
        do {
            let container = try AppContainer()
            self.container = container
            _modulesViewModel = State(initialValue: container.makeModulesViewModel())
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                viewModel: modulesViewModel,
                makeSlidesViewModel: { moduleID in
                    container.makeSlidesViewModel(moduleID: moduleID)
                },
                makeLearningViewModel: { module in
                    container.makeLearningViewModel(module: module)
                }
            )
            .frame(minWidth: 900, minHeight: 600)
            .task { modulesViewModel.load() }
        }
        .defaultSize(width: 1100, height: 720)
    }
}
