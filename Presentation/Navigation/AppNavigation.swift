import Foundation
import Observation

/// Zentraler Navigationszustand der App: aktuelles Ziel, zuletzt genutzter Bereich pro Modul
/// und ein Verlauf für „Zurück“ und „Vorwärts“. Alle Wege (Seitenleiste, Tastaturkürzel,
/// Schnellwechsler, Kalender-Sprünge) laufen über dieselben Methoden.
@MainActor
@Observable
final class AppNavigation {
    private(set) var destination: AppDestination?
    private(set) var sections: [UUID: ModuleSection]
    private(set) var backStack: [NavigationLocation] = []
    private(set) var forwardStack: [NavigationLocation] = []
    var isQuickNavigatorPresented = false
    /// Auftrag für die gerade angezeigte Modulansicht (siehe `ModuleIntent`).
    var pendingIntent: ModuleIntent?

    @ObservationIgnored private let defaults: UserDefaults
    private static let historyLimit = 50
    private static let destinationKey = "navigation.destination"
    private static let sectionsKey = "navigation.sections"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        destination = Self.restoreDestination(from: defaults)
        sections = Self.restoreSections(from: defaults)
    }

    // MARK: Zustand

    var selectedModuleID: UUID? {
        if case .module(let id) = destination { return id }
        return nil
    }

    var currentLocation: NavigationLocation? {
        guard let destination else { return nil }
        if case .module(let id) = destination {
            return NavigationLocation(destination: destination, section: section(for: id))
        }
        return NavigationLocation(destination: destination, section: nil)
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Zuletzt geöffneter Bereich eines Moduls, zunächst die Übersicht.
    func section(for moduleID: UUID) -> ModuleSection {
        sections[moduleID] ?? .overview
    }

    // MARK: Navigieren

    /// Auswahl in der Seitenleiste. Bei Modulen bleibt der zuletzt genutzte Bereich erhalten.
    func show(_ destination: AppDestination?) {
        guard let destination else { return }
        switch destination {
        case .module(let id): navigate(to: .module(id, section: section(for: id)))
        default: navigate(to: NavigationLocation(destination: destination, section: nil))
        }
    }

    func showToday() {
        navigate(to: .today)
    }

    func showCalendar() {
        navigate(to: .calendar)
    }

    func showGrades() {
        navigate(to: .grades)
    }

    func showAssignments() {
        navigate(to: .assignments)
    }

    func showExams() {
        navigate(to: .exams)
    }

    /// Öffnet ein Modul und gibt der Modulansicht einen Auftrag mit.
    func show(module id: UUID, section: ModuleSection, intent: ModuleIntent?) {
        pendingIntent = intent
        navigate(to: .module(id, section: section))
    }

    func show(module id: UUID, section: ModuleSection) {
        navigate(to: .module(id, section: section))
    }

    /// Wechselt den Bereich im aktuellen Modul. Ohne ausgewähltes Modul passiert nichts.
    func show(section: ModuleSection) {
        guard let id = selectedModuleID else { return }
        navigate(to: .module(id, section: section))
    }

    /// Opens what a Spotlight result points to.
    func open(_ target: SearchTarget) {
        switch target {
        case .module(let id): show(module: id, section: .overview)
        case .note(let moduleID, let noteID): show(module: moduleID, section: .notes, intent: .selectNote(noteID))
        case .studySheet(let moduleID, let sheetID): show(module: moduleID, section: .studySheets, intent: .selectStudySheet(sheetID))
        }
    }

    func go(to location: NavigationLocation) {
        navigate(to: location)
    }

    func goBack() {
        guard let target = backStack.popLast() else { return }
        if let current = currentLocation { forwardStack.append(current) }
        apply(target)
    }

    func goForward() {
        guard let target = forwardStack.popLast() else { return }
        if let current = currentLocation { backStack.append(current) }
        apply(target)
    }

    /// Entfernt Verweise auf gelöschte Module aus Auswahl, Verlauf und gemerkten Bereichen.
    func prune(validModuleIDs: Set<UUID>) {
        func isValid(_ location: NavigationLocation) -> Bool {
            if case .module(let id) = location.destination { return validModuleIDs.contains(id) }
            return true
        }
        backStack.removeAll { !isValid($0) }
        forwardStack.removeAll { !isValid($0) }
        sections = sections.filter { validModuleIDs.contains($0.key) }
        if let current = currentLocation, !isValid(current) {
            destination = nil
            pendingIntent = nil
        }
        persist()
    }

    // MARK: Intern

    private func navigate(to target: NavigationLocation) {
        let previous = currentLocation
        guard target != previous else { return }
        if let previous {
            backStack.append(previous)
            if backStack.count > Self.historyLimit { backStack.removeFirst() }
        }
        forwardStack.removeAll()
        apply(target)
    }

    private func apply(_ location: NavigationLocation) {
        destination = location.destination
        if case .module(let id) = location.destination, let section = location.section {
            sections[id] = section
        }
        persist()
    }

    // MARK: Persistenz

    private func persist() {
        if let destination {
            defaults.set(destination.storageKey, forKey: Self.destinationKey)
        } else {
            defaults.removeObject(forKey: Self.destinationKey)
        }
        let raw = Dictionary(uniqueKeysWithValues: sections.map { ($0.key.uuidString, $0.value.rawValue) })
        defaults.set(raw, forKey: Self.sectionsKey)
    }

    private static func restoreDestination(from defaults: UserDefaults) -> AppDestination? {
        defaults.string(forKey: destinationKey).flatMap(AppDestination.init(storageKey:))
    }

    private static func restoreSections(from defaults: UserDefaults) -> [UUID: ModuleSection] {
        let raw = defaults.dictionary(forKey: sectionsKey) as? [String: String] ?? [:]
        var result: [UUID: ModuleSection] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key), let section = ModuleSection(rawValue: value) {
                result[id] = section
            }
        }
        return result
    }
}
