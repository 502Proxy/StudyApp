import Foundation
import Observation

enum CalendarViewMode: String, CaseIterable, Identifiable {
    case month
    case agenda

    var id: Self { self }

    var title: String {
        switch self {
        case .month: "Monat"
        case .agenda: "Agenda"
        }
    }
}

/// Alle Termine eines Tages, für die Agenda-Ansicht.
struct CalendarDaySection: Identifiable, Equatable {
    let day: Date
    let events: [StudyCalendarEvent]
    var id: Date { day }
}

@MainActor
@Observable
final class StudyCalendarViewModel {
    private(set) var events: [StudyCalendarEvent] = []
    private(set) var sources: [CalendarSource] = []
    private(set) var modules: [StudyModule] = []
    private(set) var isSyncing = false

    /// Erster Tag des angezeigten Monats.
    private(set) var displayedMonth: Date
    /// Tagesbeginn des ausgewählten Tages. Es ist immer ein Tag ausgewählt (zunächst heute).
    private(set) var selectedDate: Date

    var mode: CalendarViewMode = .month
    var searchText = ""
    var selectedEvent: StudyCalendarEvent?
    var errorMessage: String?
    private(set) var statusMessage: String?
    /// Zeitpunkt, auf den sich „läuft gerade“ und „als Nächstes“ beziehen. Wird über `tick()` fortgeschrieben.
    private(set) var referenceDate: Date

    /// Wird aufgerufen, wenn der Kalender Module angelegt hat, damit die Modulliste neu lädt.
    @ObservationIgnored var onModulesChanged: (() -> Void)?

    let calendar: Calendar
    private let now: () -> Date
    private let settings: any StudySettingsStore
    private var eventsByDay: [Date: [StudyCalendarEvent]] = [:]
    private var modulesByID: [UUID: StudyModule] = [:]
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    private let moduleRepository: any ModuleRepository
    private let listCalendar: ListStudyCalendarUseCase
    private let importFileUseCase: ImportCalendarFileUseCase
    private let syncSubscription: SyncCalendarSubscriptionUseCase
    private let linkEvent: LinkCalendarEventToModuleUseCase
    private let removeSource: RemoveCalendarSourceUseCase
    private let syncModules: SyncModulesWithCalendarUseCase
    private let applyCandidates: ApplyModuleCandidatesUseCase
    private let detectCandidates: DetectModuleCandidatesUseCase

    init(
        repository: any StudyCalendarRepository,
        moduleRepository: any ModuleRepository,
        feedLoader: any CalendarFeedLoader,
        parser: any CalendarEventParsing,
        calendar: Calendar = .current,
        settings: any StudySettingsStore,
        now: @escaping () -> Date = { .now }
    ) {
        self.calendar = calendar
        self.now = now
        self.settings = settings
        self.moduleRepository = moduleRepository
        listCalendar = ListStudyCalendarUseCase(repository: repository)
        importFileUseCase = ImportCalendarFileUseCase(repository: repository, parser: parser)
        syncSubscription = SyncCalendarSubscriptionUseCase(repository: repository, loader: feedLoader, parser: parser)
        linkEvent = LinkCalendarEventToModuleUseCase(repository: repository)
        removeSource = RemoveCalendarSourceUseCase(repository: repository)
        var detect = DetectModuleCandidatesUseCase()
        detect.calendar = calendar
        detectCandidates = detect
        syncModules = SyncModulesWithCalendarUseCase(
            moduleRepository: moduleRepository, calendarRepository: repository, detect: detect, now: now
        )
        applyCandidates = ApplyModuleCandidatesUseCase(
            moduleRepository: moduleRepository, calendarRepository: repository, now: now
        )

        let current = now()
        referenceDate = current
        let today = calendar.startOfDay(for: current)
        selectedDate = today
        displayedMonth = CalendarMonthGrid.startOfMonth(containing: today, calendar: calendar)
    }

    // MARK: Abgeleitete Daten

    var weeks: [[Date]] { CalendarMonthGrid.weeks(for: displayedMonth, calendar: calendar) }
    var weekdaySymbols: [String] { CalendarMonthGrid.weekdaySymbols(calendar: calendar) }
    var today: Date { calendar.startOfDay(for: now()) }
    var selectedDayEvents: [StudyCalendarEvent] { events(on: selectedDate) }
    var todayEventCount: Int { events(on: today).count }
    var hasSubscriptions: Bool { sources.contains { $0.kind == .subscription } }
    var isEmpty: Bool { events.isEmpty && sources.isEmpty }

    func events(on date: Date) -> [StudyCalendarEvent] {
        eventsByDay[calendar.startOfDay(for: date)] ?? []
    }

    func module(for event: StudyCalendarEvent) -> StudyModule? {
        event.moduleID.flatMap { modulesByID[$0] }
    }

    func eventCount(for source: CalendarSource) -> Int {
        events.lazy.filter { $0.sourceID == source.id }.count
    }

    func isInDisplayedMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
    }

    /// Termine ab dem ausgewählten Tag, nach Tagen gruppiert.
    var agendaSections: [CalendarDaySection] {
        eventsByDay.keys
            .filter { $0 >= selectedDate }
            .sorted()
            .map { CalendarDaySection(day: $0, events: eventsByDay[$0] ?? []) }
    }

    var isSearching: Bool { !trimmedSearch.isEmpty }

    var searchResults: [StudyCalendarEvent] {
        let query = trimmedSearch
        guard !query.isEmpty else { return [] }
        return events.filter { event in
            let moduleName = module(for: event)?.name ?? ""
            return [event.title, event.location, event.details, moduleName].contains { $0.localizedStandardContains(query) }
        }
    }

    func upcomingEvents(forModule moduleID: UUID, limit: Int = 3) -> [StudyCalendarEvent] {
        events.upcoming(after: referenceDate, moduleID: moduleID, limit: limit)
    }

    // MARK: Jetzt und als Nächstes

    /// Vorlesung (oder anderer Modultermin), die gerade läuft oder gleich beginnt.
    var currentLecture: StudyCalendarEvent? {
        LectureSchedule.current(in: events, at: referenceDate, leadTime: settings.lectureLeadTime)
    }

    /// Nächster Modultermin nach dem aktuellen.
    var nextLecture: StudyCalendarEvent? {
        LectureSchedule.next(in: events, after: max(referenceDate, currentLecture?.startDate ?? referenceDate))
    }

    /// Termine des heutigen Tages bezogen auf `referenceDate`.
    var todayEvents: [StudyCalendarEvent] {
        eventsByDay[calendar.startOfDay(for: referenceDate)] ?? []
    }

    /// Anteil der bereits verstrichenen Zeit eines Termins (0…1).
    func progress(of event: StudyCalendarEvent) -> Double {
        let total = event.endDate.timeIntervalSince(event.startDate)
        guard total > 0 else { return 0 }
        return min(max(referenceDate.timeIntervalSince(event.startDate) / total, 0), 1)
    }

    /// Modul, dessen Termin gerade läuft – für die Live-Markierung in der Seitenleiste.
    var liveModuleID: UUID? { currentLecture?.moduleID }

    /// Schreibt die Bezugszeit fort; die App ruft das regelmäßig auf.
    func tick() {
        referenceDate = now()
    }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Laden

    func load() {
        referenceDate = now()
        do {
            let result = try listCalendar()
            events = result.events
            sources = result.sources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            modules = try moduleRepository.all().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            modulesByID = Dictionary(modules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            rebuildDayIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rebuildDayIndex() {
        var index: [Date: [StudyCalendarEvent]] = [:]
        for event in events {
            for day in event.occupiedDays(calendar: calendar) {
                index[day, default: []].append(event)
            }
        }
        eventsByDay = index.mapValues { $0.sorted(by: StudyCalendarEvent.displayOrder) }
    }

    // MARK: Navigation im Kalender

    /// Wählt einen Tag aus und wechselt bei Bedarf in dessen Monat.
    func select(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        selectedDate = day
        if !isInDisplayedMonth(day) {
            displayedMonth = CalendarMonthGrid.startOfMonth(containing: day, calendar: calendar)
        }
    }

    func moveSelection(byDays days: Int) {
        guard let date = calendar.date(byAdding: .day, value: days, to: selectedDate) else { return }
        select(date)
    }

    /// Blättert um ganze Monate und nimmt die Auswahl mit (am Monatsende auf den letzten Tag begrenzt).
    func showMonth(offset: Int) {
        guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth),
              let day = calendar.date(byAdding: .month, value: offset, to: selectedDate) else { return }
        displayedMonth = CalendarMonthGrid.startOfMonth(containing: month, calendar: calendar)
        selectedDate = calendar.startOfDay(for: day)
    }

    func goToToday() {
        select(now())
    }

    /// Zeigt einen Termin im Monatsraster, z. B. nach einem Klick in der Suche oder in der Modulübersicht.
    func reveal(_ event: StudyCalendarEvent) {
        searchText = ""
        mode = .month
        select(event.startDate)
    }

    // MARK: Import und Abos

    func importFiles(_ urls: [URL]) {
        var imported = 0
        for url in urls {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let standardized = url.standardizedFileURL
                let existing = sources.first { $0.kind == .file && $0.url?.standardizedFileURL == standardized }
                imported += try importFileUseCase(data: data, fileURL: url, existing: existing)
                load()
            } catch {
                errorMessage = "„\(url.lastPathComponent)“: \(error.localizedDescription)"
            }
        }
        if imported > 0 {
            let modules = synchronizeModules()
            announce(Self.summary("\(Self.eventCountText(imported)) importiert", modules: modules))
        }
    }

    /// Abonniert einen Feed. Fehler werden geworfen, damit das Formular sie direkt anzeigen kann.
    func subscribe(to address: String) async throws {
        let url = try CalendarFeedURL.normalized(address)
        isSyncing = true
        defer { isSyncing = false }
        let existing = sources.first { $0.kind == .subscription && $0.url == url }
        let count = try await syncSubscription(url: url, existing: existing)
        load()
        let modules = synchronizeModules()
        announce(Self.summary("Kalender abonniert: \(Self.eventCountText(count))", modules: modules))
    }

    func refresh(_ source: CalendarSource) async {
        guard source.kind == .subscription, let url = source.url else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let count = try await syncSubscription(url: url, existing: source)
            load()
            let modules = synchronizeModules()
            announce(Self.summary("„\(source.name)“ aktualisiert: \(Self.eventCountText(count))", modules: modules))
        } catch {
            errorMessage = "„\(source.name)“ konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func refreshAll() async {
        let subscriptions = sources.filter { $0.kind == .subscription }
        guard !subscriptions.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }

        var failures: [String] = []
        for source in subscriptions {
            guard let url = source.url else { continue }
            do {
                _ = try await syncSubscription(url: url, existing: source)
            } catch {
                failures.append("„\(source.name)“: \(error.localizedDescription)")
            }
        }
        load()
        let modules = synchronizeModules()
        if failures.isEmpty {
            announce(Self.summary("Alle Abonnements aktualisiert", modules: modules))
        } else {
            errorMessage = "Nicht alle Abonnements konnten aktualisiert werden:\n" + failures.joined(separator: "\n")
        }
    }

    func deleteSource(_ source: CalendarSource) {
        do {
            try removeSource(source)
            load()
            announce("„\(source.name)“ und die importierten Termine wurden entfernt.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Abonnements, deren letzter Abgleich länger zurückliegt, werden beim Start aktualisiert.
    static let refreshInterval: TimeInterval = 3 * 3_600

    /// Aktualisiert Abonnements, deren letzter Abgleich länger als `refreshInterval` her ist.
    /// Läuft beim Start im Hintergrund; Fehler (z. B. offline) bleiben still.
    func refreshStaleSubscriptions() async {
        guard settings.autoRefreshCalendars, !isSyncing else { return }
        let threshold = now().addingTimeInterval(-Self.refreshInterval)
        let stale = sources.filter { $0.kind == .subscription && ($0.lastSyncedAt ?? .distantPast) < threshold }
        guard !stale.isEmpty else { return }
        isSyncing = true
        defer { isSyncing = false }
        var updated = 0
        for source in stale {
            guard let url = source.url else { continue }
            if (try? await syncSubscription(url: url, existing: source)) != nil { updated += 1 }
        }
        guard updated > 0 else { return }
        load()
        let modules = synchronizeModules()
        if !modules.isEmpty { announce(Self.summary("Stundenplan aktualisiert", modules: modules)) }
    }

    // MARK: Modulverknüpfung

    /// Verknüpft einen Termin mit einem Modul. Mit `applyToSeries` erhalten alle Termine derselben
    /// Veranstaltung (gleicher Titel, auch Übung/Tutorium) dieselbe Zuordnung.
    func link(_ event: StudyCalendarEvent, to moduleID: UUID?, applyToSeries: Bool = false) {
        do {
            if applyToSeries {
                let ids = seriesEvents(for: event).map(\.id)
                try linkEvent(eventIDs: ids, moduleID: moduleID)
            } else {
                try linkEvent(eventID: event.id, moduleID: moduleID)
            }
            load()
            if selectedEvent?.id == event.id {
                selectedEvent = events.first { $0.id == event.id }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Alle Termine derselben Lehrveranstaltung wie `event` (einschließlich `event`).
    func seriesEvents(for event: StudyCalendarEvent) -> [StudyCalendarEvent] {
        guard let key = CourseTitleAnalyzer.analyze(event.title)?.key else {
            return events.filter { $0.title == event.title }
        }
        return events.filter { CourseTitleAnalyzer.analyze($0.title)?.key == key }
    }

    // MARK: Module aus dem Kalender

    /// Alle erkannten Lehrveranstaltungen, für die Übersicht „Module erkennen“.
    func moduleCandidates() -> [ModuleCandidate] {
        detectCandidates(events: events, modules: modules, now: now())
    }

    var ignoredCourseKeys: Set<String> {
        settings.ignoredCourseKeys
    }

    /// Übernimmt die ausgewählten Kandidaten; nicht ausgewählte werden künftig nicht mehr automatisch angelegt.
    func applyModuleCandidates(_ selected: [ModuleCandidate], rejected: [ModuleCandidate]) {
        var ignored = ignoredCourseKeys
        ignored.subtract(selected.map(\.key))
        ignored.formUnion(rejected.filter { $0.existingModuleID == nil }.map(\.key))
        settings.ignoredCourseKeys = ignored
        do {
            let result = try applyCandidates(selected)
            load()
            if !result.createdModules.isEmpty { onModulesChanged?() }
            announce(Self.summary(result.isEmpty ? "Keine Änderungen" : "Stundenplan übernommen", modules: result.createdModules, linked: result.linkedEventCount))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Automatischer Abgleich nach Import oder Aktualisierung (siehe `SyncModulesWithCalendarUseCase`).
    /// - Returns: Neu angelegte Module.
    @discardableResult
    func synchronizeModules() -> [StudyModule] {
        do {
            let result = try syncModules(
                ignoredKeys: ignoredCourseKeys,
                createModules: settings.autoCreateModules
            )
            guard !result.isEmpty else { return [] }
            load()
            if !result.createdModules.isEmpty { onModulesChanged?() }
            return result.createdModules
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    /// Merkt eine Veranstaltung als „kein Modul“, z. B. nachdem das automatisch angelegte Modul gelöscht wurde.
    func ignoreCourse(named name: String) {
        var ignored = ignoredCourseKeys
        ignored.insert(CourseTitleAnalyzer.analyze(name)?.key ?? CourseTitleAnalyzer.makeKey(name))
        settings.ignoredCourseKeys = ignored
    }

    // MARK: Hilfen

    /// Kurze Statusmeldung von außen, z. B. vom Vorlesungs-Autopiloten.
    func notify(_ message: String) {
        announce(message)
    }

    /// Zeigt eine kurze Statusmeldung, die sich nach einigen Sekunden von selbst ausblendet.
    private func announce(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    static func eventCountText(_ count: Int) -> String {
        count == 1 ? "1 Termin" : "\(count) Termine"
    }

    /// Statusmeldung samt neu angelegter Module, z. B. „12 Termine importiert · 2 neue Module: Analysis I, Physik“.
    static func summary(_ base: String, modules: [StudyModule], linked: Int = 0) -> String {
        var parts = [base]
        if !modules.isEmpty {
            let names = modules.prefix(3).map(\.name).joined(separator: ", ")
            let more = modules.count > 3 ? " …" : ""
            parts.append(modules.count == 1 ? "neues Modul: \(names)" : "\(modules.count) neue Module: \(names)\(more)")
        } else if linked > 0 {
            parts.append("\(eventCountText(linked)) verknüpft")
        }
        return parts.joined(separator: " · ") + "."
    }
}
