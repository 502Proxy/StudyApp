import AppKit
import Observation
import SwiftUI

/// The StudyApp item in the menu bar, built with AppKit (`NSStatusItem` and a popover).
///
/// SwiftUI's `MenuBarExtra` scene kept the app's scene graph changing at launch, so the main
/// window rebuilt its toolbar endlessly and the app hung. A status item owned by the app avoids
/// the extra scene; the popover still shows the SwiftUI `MenuBarContent`.
@MainActor
final class MenuBarController: NSObject {
    private let calendar: StudyCalendarViewModel
    private let today: TodayViewModel
    private let studyTimer: StudyTimerViewModel
    private let navigation: AppNavigation
    private let defaults: UserDefaults
    private var statusItem: NSStatusItem?
    private var defaultsObserver: NSObjectProtocol?
    private lazy var popover: NSPopover = makePopover()

    init(
        calendar: StudyCalendarViewModel,
        today: TodayViewModel,
        studyTimer: StudyTimerViewModel,
        navigation: AppNavigation,
        defaults: UserDefaults = .standard
    ) {
        self.calendar = calendar
        self.today = today
        self.studyTimer = studyTimer
        self.navigation = navigation
        self.defaults = defaults
    }

    /// Shows the item when the setting is on and follows later changes of the setting.
    func install() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyVisibility() }
        }
        applyVisibility()
    }

    // MARK: Visibility

    private var isEnabled: Bool {
        defaults.object(forKey: ViewPreferences.showsMenuBarItemKey) as? Bool ?? true
    }

    private func applyVisibility() {
        if isEnabled, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(togglePopover(_:))
            item.button?.imagePosition = .imageLeading
            statusItem = item
            observeSummary()
        } else if !isEnabled, let item = statusItem {
            popover.performClose(nil)
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    // MARK: Label

    /// Updates the label now and again whenever the lecture, the due cards or the study timer change.
    private func observeSummary() {
        guard statusItem != nil else { return }
        let summary = withObservationTracking {
            MenuBarSummary(calendar: calendar, dueCards: today.totalDue, studyTimer: studyTimer)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSummary() }
        }
        updateLabel(summary)
    }

    private func updateLabel(_ summary: MenuBarSummary) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: summary.symbolName, accessibilityDescription: "StudyApp")
        button.title = summary.title.isEmpty ? "" : " \(summary.title)"
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarPopoverView(
            calendar: calendar,
            today: today,
            studyTimer: studyTimer,
            onOpenLecture: { [weak self] moduleID in
                self?.openMainWindow()
                self?.navigation.show(module: moduleID, section: .slides, intent: .resumeSlides)
            },
            onReviewCards: { [weak self] in
                guard let self else { return }
                openMainWindow()
                // Starts with the module that has the most due cards, like „Lernen starten“ on Today.
                if let moduleID = today.dueCounts.max(by: { $0.value < $1.value })?.key {
                    navigation.show(module: moduleID, section: .flashcards)
                }
            },
            onOpenApp: { [weak self] in self?.openMainWindow() }
        ))
        return popover
    }

    /// Closes the popover and brings the main window to the front.
    private func openMainWindow() {
        popover.performClose(nil)
        NSApplication.shared.activate()
        NSApplication.shared.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }
}
