import AppKit
import SwiftUI

@main
struct StudyAppApp: App {
    private let container: AppContainer
    private let autopilot: LectureAutopilot
    @State private var modulesViewModel: ModulesViewModel
    @State private var calendarViewModel: StudyCalendarViewModel
    @State private var todayViewModel: TodayViewModel
    @State private var navigation: AppNavigation
    @AppStorage(ViewPreferences.appearanceKey) private var appearance = AppAppearance.light

    init() {
        do {
            let container = try AppContainer()
            let modules = container.makeModulesViewModel()
            let calendar = container.makeStudyCalendarViewModel()
            let today = container.makeTodayViewModel()
            let navigation = AppNavigation()
            // Vom Kalender angelegte Module sofort in Seitenleiste und Startseite zeigen.
            calendar.onModulesChanged = {
                modules.load()
                today.load()
            }
            self.container = container
            autopilot = LectureAutopilot(
                navigation: navigation, calendar: calendar, modules: modules, settings: container.preferences
            )
            _modulesViewModel = State(initialValue: modules)
            _calendarViewModel = State(initialValue: calendar)
            _todayViewModel = State(initialValue: today)
            _navigation = State(initialValue: navigation)
        } catch {
            fatalError("Datenbank konnte nicht geöffnet werden: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                viewModel: modulesViewModel,
                navigation: navigation,
                calendarViewModel: calendarViewModel,
                todayViewModel: todayViewModel,
                makeSlidesViewModel: { moduleID in
                    container.makeSlidesViewModel(moduleID: moduleID)
                },
                makeLearningViewModel: { module in
                    container.makeLearningViewModel(module: module)
                }
            )
            .frame(minWidth: 960, minHeight: 640)
            .tint(Theme.accent)
            .preferredColorScheme(appearance.colorScheme)
            .task { await startUp() }
            .task { await keepClockRunning() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                autopilot.run(isLaunch: false)
            }
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            // Eine App, ein Fenster: ⌘N gehört der „Neuen Notiz“.
            CommandGroup(replacing: .newItem) {}
            AppCommands(navigation: navigation, calendar: calendarViewModel)
        }

        Settings {
            SettingsView(settings: container.preferences)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    /// Daten laden, Stundenplan abgleichen und – falls gerade eine Vorlesung läuft – direkt deren Folien öffnen.
    private func startUp() async {
        modulesViewModel.load()
        calendarViewModel.load()
        calendarViewModel.synchronizeModules()
        todayViewModel.load()
        if navigation.destination == nil {
            navigation.showToday()
        }
        autopilot.run(isLaunch: true)

        // Abonnements im Hintergrund auffrischen; eine dabei neu erkannte Vorlesung wird ebenfalls geöffnet.
        await calendarViewModel.refreshStaleSubscriptions()
        autopilot.run(isLaunch: false)
    }

    /// Hält „läuft gerade“, Fortschrittsbalken und „als Nächstes“ aktuell.
    private func keepClockRunning() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            calendarViewModel.tick()
        }
    }
}
