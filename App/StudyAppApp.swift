import AppKit
import SwiftUI

@main
struct StudyAppApp: App {
    private let container: AppContainer
    private let autopilot: LectureAutopilot
    @State private var modulesViewModel: ModulesViewModel
    @State private var calendarViewModel: StudyCalendarViewModel
    @State private var todayViewModel: TodayViewModel
    @State private var assignmentsViewModel: AssignmentsViewModel
    @State private var navigation: AppNavigation
    @State private var studIPViewModel: StudIPViewModel
    @State private var backupViewModel: BackupViewModel
    @State private var updater = AppUpdater()
    @AppStorage(ViewPreferences.appearanceKey) private var appearance = AppAppearance.light

    init() {
        do {
            let container = try AppContainer()
            let modules = container.makeModulesViewModel()
            let calendar = container.makeStudyCalendarViewModel()
            let today = container.makeTodayViewModel()
            let assignments = container.makeAssignmentsViewModel()
            let navigation = AppNavigation()
            let studIP = container.makeStudIPViewModel()
            // Neu verknüpfte Veranstaltungen und geladene Folien sofort in Seitenleiste und Startseite zeigen.
            studIP.onSlidesChanged = {
                modules.load()
                today.load()
            }
            // Vom Kalender angelegte Module sofort in Seitenleiste und Startseite zeigen.
            calendar.onModulesChanged = {
                modules.load()
                today.load()
                assignments.load()
            }
            self.container = container
            autopilot = LectureAutopilot(
                navigation: navigation, calendar: calendar, modules: modules, settings: container.preferences
            )
            _modulesViewModel = State(initialValue: modules)
            _calendarViewModel = State(initialValue: calendar)
            _todayViewModel = State(initialValue: today)
            _assignmentsViewModel = State(initialValue: assignments)
            _navigation = State(initialValue: navigation)
            _studIPViewModel = State(initialValue: studIP)
            let backup = container.makeBackupViewModel()
            // After a restore every screen shows the restored data.
            backup.onRestored = {
                modules.load()
                calendar.load()
                today.load()
                assignments.load()
            }
            _backupViewModel = State(initialValue: backup)
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
                assignmentsViewModel: assignmentsViewModel,
                studIPViewModel: studIPViewModel,
                backupViewModel: backupViewModel,
                makeSlidesViewModel: { moduleID in
                    container.makeSlidesViewModel(moduleID: moduleID)
                },
                makeLearningViewModel: { module in
                    container.makeLearningViewModel(module: module)
                },
                makeCourseFilesViewModel: { module in
                    container.makeCourseFilesViewModel(module: module)
                }
            )
            .frame(minWidth: 960, minHeight: 640)
            .tint(Theme.accent)
            .preferredColorScheme(appearance.colorScheme)
            .task { await startUp() }
            .task { await keepClockRunning() }
            .task { await keepSourcesFresh() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                autopilot.run(isLaunch: false)
                Task {
                    await calendarViewModel.refreshStaleSubscriptions()
                    autopilot.run(isLaunch: false)
                }
            }
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            // Eine App, ein Fenster: ⌘N gehört der „Neuen Notiz“.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            AppCommands(navigation: navigation, calendar: calendarViewModel, assignments: assignmentsViewModel)
            BackupCommands(viewModel: backupViewModel)
        }

        Settings {
            SettingsView(settings: container.preferences, updater: updater, studIP: studIPViewModel, backup: backupViewModel)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }

    /// Daten laden, Stundenplan abgleichen und – falls gerade eine Vorlesung läuft – direkt deren Folien öffnen.
    private func startUp() async {
        modulesViewModel.load()
        calendarViewModel.load()
        assignmentsViewModel.load()
        calendarViewModel.synchronizeModules()
        todayViewModel.load()
        if navigation.destination == nil {
            navigation.showToday()
        }
        autopilot.run(isLaunch: true)

        // Abonnements im Hintergrund auffrischen; eine dabei neu erkannte Vorlesung wird ebenfalls geöffnet.
        await calendarViewModel.refreshStaleSubscriptions()
        autopilot.run(isLaunch: false)
        await studIPViewModel.syncIfDue()
        await backupViewModel.runAutomaticBackupIfDue()
    }

    /// Hält „läuft gerade“, Fortschrittsbalken und „als Nächstes“ aktuell.
    private func keepClockRunning() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            calendarViewModel.tick()
            assignmentsViewModel.tick()
        }
    }

    /// Holt geänderte Termine (Raumwechsel, Ausfälle) und neue Folien auch bei durchgehend geöffneter App.
    /// Läuft getrennt von der Uhr, damit ein langsamer Download die Anzeige nicht aufhält.
    private func keepSourcesFresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            await calendarViewModel.refreshStaleSubscriptions()
            await studIPViewModel.syncIfDue()
        }
    }
}
