import AppKit
import AppIntents
import SwiftUI

@main
struct StudyAppApp: App {
    private let container: AppContainer
    private let autopilot: LectureAutopilot
    /// Installed in `init` so a click that launches the app is not lost.
    private let notificationResponder: NotificationResponder
    @State private var modulesViewModel: ModulesViewModel
    @State private var calendarViewModel: StudyCalendarViewModel
    @State private var todayViewModel: TodayViewModel
    @State private var assignmentsViewModel: AssignmentsViewModel
    @State private var navigation: AppNavigation
    @State private var studIPViewModel: StudIPViewModel
    @State private var backupViewModel: BackupViewModel
    @State private var notificationsViewModel: NotificationsViewModel
    @State private var examsViewModel: ExamsViewModel
    @State private var announcementsViewModel: AnnouncementsViewModel
    @State private var studyTimerViewModel: StudyTimerViewModel
    @State private var updater = AppUpdater()
    @AppStorage(ViewPreferences.appearanceKey) private var appearance = AppAppearance.standard
    @AppStorage(ViewPreferences.showsMenuBarItemKey) private var showsMenuBarItem = true

    init() {
        do {
            let container = try AppContainer()
            let modules = container.makeModulesViewModel()
            let calendar = container.makeStudyCalendarViewModel()
            let today = container.makeTodayViewModel()
            let assignments = container.makeAssignmentsViewModel()
            let exams = container.makeExamsViewModel()
            let navigation = AppNavigation()
            let studIP = container.makeStudIPViewModel()
            let announcements = container.makeAnnouncementsViewModel()
            studIP.onAnnouncementsSynced = { announcements.load() }
            studIP.onTimetableSynced = { calendar.load() }
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
                exams.load()
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
            let intentServices = StudyAppIntentServices(container: container, navigation: navigation)
            AppDependencyManager.shared.add(dependency: intentServices)
            _studIPViewModel = State(initialValue: studIP)
            let notifications = container.makeNotificationsViewModel()
            studIP.onBackgroundSyncChanges = { summary in
                Task { await notifications.notifyAfterSync(summary) }
            }
            _notificationsViewModel = State(initialValue: notifications)
            let responder = NotificationResponder()
            responder.onOpen = { target in
                Self.open(target, navigation: navigation)
            }
            responder.install()
            notificationResponder = responder
            let studyTimer = container.makeStudyTimerViewModel()
            let backup = container.makeBackupViewModel()
            // After a restore every screen shows the restored data.
            backup.onRestored = {
                modules.load()
                calendar.load()
                today.load()
                assignments.load()
                exams.load()
                announcements.load()
                studyTimer.load()
                Task { await notifications.refresh() }
            }
            _backupViewModel = State(initialValue: backup)
            _examsViewModel = State(initialValue: exams)
            _announcementsViewModel = State(initialValue: announcements)
            _studyTimerViewModel = State(initialValue: studyTimer)
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
                examsViewModel: examsViewModel,
                announcementsViewModel: announcementsViewModel,
                studyTimerViewModel: studyTimerViewModel,
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
                    await studIPViewModel.refreshSessionState(force: false)
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

        MenuBarExtra(isInserted: $showsMenuBarItem) {
            MenuBarSummaryReader(calendar: calendarViewModel, today: todayViewModel) { summary in
                MenuBarContent(
                    summary: summary,
                    onOpenLecture: { moduleID in
                        Self.bringToFront()
                        navigation.show(module: moduleID, section: .slides, intent: .resumeSlides)
                    },
                    onReviewCards: {
                        Self.bringToFront()
                        // Starts with the module that has the most due cards, like „Lernen starten“ on Today.
                        if let moduleID = todayViewModel.dueCounts.max(by: { $0.value < $1.value })?.key {
                            navigation.show(module: moduleID, section: .flashcards)
                        }
                    },
                    onOpenApp: { Self.bringToFront() }
                )
                .tint(Theme.accent)
                .preferredColorScheme(appearance.colorScheme)
            }
        } label: {
            MenuBarSummaryReader(calendar: calendarViewModel, today: todayViewModel) { summary in
                MenuBarLabel(summary: summary)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                settings: container.preferences,
                updater: updater,
                studIP: studIPViewModel,
                backup: backupViewModel,
                notifications: notificationsViewModel
            )
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
        examsViewModel.load()
        announcementsViewModel.load()
        // Lets Siri offer the current modules in „Starte Karteikarten …“.
        StudyAppShortcuts.updateAppShortcutParameters()
        if navigation.destination == nil {
            navigation.showToday()
        }
        autopilot.run(isLaunch: true)

        // Abonnements im Hintergrund auffrischen; eine dabei neu erkannte Vorlesung wird ebenfalls geöffnet.
        await calendarViewModel.refreshStaleSubscriptions()
        autopilot.run(isLaunch: false)
        await studIPViewModel.refreshSessionState()
        await studIPViewModel.syncIfDue()
        await backupViewModel.runAutomaticBackupIfDue()
        await notificationsViewModel.refresh()
    }

    /// Shows the main window, e.g. after a click in the menu bar.
    private static func bringToFront() {
        NSApplication.shared.activate()
        NSApplication.shared.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    /// Opens what a clicked notification refers to.
    private static func open(_ target: NotificationTarget, navigation: AppNavigation) {
        NSApplication.shared.activate()
        switch target {
        case .lecture(let moduleID): navigation.show(module: moduleID, section: .slides, intent: .resumeSlides)
        case .assignment(let moduleID): navigation.show(module: moduleID, section: .assignments)
        case .today: navigation.showToday()
        }
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
            // Picks up new or moved lectures and assignments.
            await notificationsViewModel.refresh()
        }
    }
}
