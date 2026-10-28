import Foundation
import Observation

/// Anmeldung bei Stud.IP, Zuordnung der Veranstaltungen zu Modulen und Laden neuer Folien.
@MainActor
@Observable
final class StudIPViewModel {
    static let defaultServer = "https://elearning.uni-oldenburg.de"
    /// Automatischer Folienabgleich höchstens so oft.
    static let autoSyncInterval: TimeInterval = 3 * 3_600

    private(set) var account: StudIPAccount?
    private(set) var courses: [StudIPCourse] = []
    private(set) var isLoadingCourses = false
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var statusMessage: String?
    /// Die Browser-Sitzung ist abgelaufen; Abgleiche pausieren bis zur erneuten Anmeldung.
    private(set) var sessionExpired = false
    /// Erhöht sich nach jedem Abgleich mit neuen Folien oder Dateien, damit offene Module ihre Listen neu laden.
    private(set) var slidesRevision = 0
    var errorMessage: String?

    var autoSyncSlides = true {
        didSet { store.autoSyncSlides = autoSyncSlides }
    }

    var isConnected: Bool { account != nil }
    var usesBrowserLogin: Bool { store.load()?.usesSession ?? false }

    /// Adresse für die Browser-Anmeldung: der bisherige Server oder der der Uni Oldenburg.
    var loginServer: URL {
        account?.serverURL ?? (try? StudIPServerURL.normalized(Self.defaultServer)) ?? URL(string: Self.defaultServer)!
    }

    /// Wird nach geladenen Folien aufgerufen, z. B. um Zähler auf der Startseite zu aktualisieren.
    @ObservationIgnored var onSlidesChanged: (() -> Void)?
    /// Called when an automatic sync brought new material, e.g. to post a notification.
    @ObservationIgnored var onBackgroundSyncChanges: ((StudIPSyncSummary) -> Void)?
    /// Called after announcements were synced, so lists showing them can reload.
    @ObservationIgnored var onAnnouncementsSynced: (() -> Void)?
    /// Called after the Stud.IP timetable was imported, so the calendar can reload.
    @ObservationIgnored var onTimetableSynced: (() -> Void)?

    private let store: any StudIPAccountStore
    private let moduleRepository: any ModuleRepository
    private let connectUseCase: ConnectStudIPUseCase
    private let checkSession: CheckStudIPSessionUseCase
    private let linkCourse: LinkStudIPCourseUseCase
    private let syncCourses: SyncStudIPCoursesUseCase
    private let syncAnnouncements: SyncAnnouncementsUseCase?
    private let syncTimetable: SyncStudIPTimetableUseCase?
    private let settings: (any StudySettingsStore)?
    private let service: any StudIPService
    private let now: () -> Date
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var lastSessionCheck: Date?
    /// Checking on every app activation would mean a request per app switch.
    static let sessionCheckInterval: TimeInterval = 15 * 60

    init(
        service: any StudIPService,
        store: any StudIPAccountStore,
        moduleRepository: any ModuleRepository,
        slideRepository: any SlideDocumentRepository,
        importer: ImportSlideDocumentUseCase,
        fileRepository: (any CourseFileRepository)? = nil,
        storage: (any FileStorage)? = nil,
        announcementSync: SyncAnnouncementsUseCase? = nil,
        timetableSync: SyncStudIPTimetableUseCase? = nil,
        settings: (any StudySettingsStore)? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.store = store
        self.moduleRepository = moduleRepository
        self.now = now
        connectUseCase = ConnectStudIPUseCase(service: service, store: store)
        checkSession = CheckStudIPSessionUseCase(service: service, store: store)
        var removeFiles: RemoveCourseFilesUseCase?
        if let fileRepository, let storage {
            removeFiles = RemoveCourseFilesUseCase(repository: fileRepository, storage: storage)
        }
        linkCourse = LinkStudIPCourseUseCase(repository: moduleRepository, removeFiles: removeFiles)
        syncCourses = SyncStudIPCoursesUseCase(
            slideRepository: slideRepository, service: service, importer: importer,
            fileRepository: fileRepository, storage: storage
        )
        syncAnnouncements = announcementSync
        syncTimetable = timetableSync
        self.settings = settings
        account = store.load()?.account
        lastSync = store.lastSlideSync
        autoSyncSlides = store.autoSyncSlides
    }

    // MARK: Anmeldung

    /// Fehler werden geworfen, damit das Formular sie direkt anzeigen kann.
    func connect(server: String, username: String, password: String) async throws {
        let name = try await connectUseCase(server: server, username: username, password: password)
        didConnect(name)
    }

    /// Prüft nach jedem Seitenaufruf im Anmeldefenster, ob die Sitzung angemeldet ist.
    /// - Returns: `true`, sobald die Anmeldung übernommen wurde.
    func connect(server: URL, cookieHeader: String) async -> Bool {
        guard let name = try? await connectUseCase(server: server, cookieHeader: cookieHeader) else { return false }
        let wasExpired = sessionExpired
        didConnect(name)
        if wasExpired {
            // Catch up on what the paused background sync missed.
            Task { await syncNow() }
        }
        return true
    }

    /// Checks the stored sign-in on launch and when the app becomes active. Offline results leave the
    /// state unchanged, so a missing network does not ask for a new sign-in.
    func refreshSessionState(force: Bool = true) async {
        let reference = now()
        if !force, let lastSessionCheck, reference.timeIntervalSince(lastSessionCheck) < Self.sessionCheckInterval { return }
        lastSessionCheck = reference
        switch await checkSession() {
        case .valid: sessionExpired = false
        case .expired: sessionExpired = true
        case .unknown, .notConnected: break
        }
    }

    private func didConnect(_ name: String) {
        account = store.load()?.account
        courses = []
        sessionExpired = false
        announce("Mit Stud.IP verbunden als \(name).")
    }

    func disconnect() {
        store.delete()
        account = nil
        courses = []
        lastSync = nil
        sessionExpired = false
    }

    // MARK: Veranstaltungen

    /// Veranstaltungen, neueste Semester zuerst.
    func loadCourses() async {
        guard let credentials = store.load(), !isLoadingCourses else { return }
        isLoadingCourses = true
        defer { isLoadingCourses = false }
        do {
            courses = try await service.courses(credentials).sorted(by: Self.newestFirst)
        } catch {
            noteSessionExpiry(error)
            errorMessage = error.localizedDescription
        }
    }

    func course(withID id: String?) -> StudIPCourse? {
        guard let id else { return nil }
        return courses.first { $0.id == id }
    }

    func suggestion(for module: StudyModule) -> StudIPCourse? {
        StudIPCourseMatcher.bestCourse(for: module, in: courses)
    }

    func link(_ module: StudyModule, to courseID: String?) {
        do {
            try linkCourse(module, courseID: courseID)
            slidesRevision += 1
            onSlidesChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Übernimmt für alle noch nicht verknüpften Module den Vorschlag.
    /// - Returns: Anzahl neu verknüpfter Module.
    @discardableResult
    func applySuggestions(to modules: [StudyModule]) -> Int {
        var linked = 0
        for module in modules where module.studIPCourseID == nil {
            guard let course = suggestion(for: module) else { continue }
            do {
                try linkCourse(module, courseID: course.id)
                linked += 1
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        if linked > 0 { onSlidesChanged?() }
        return linked
    }

    // MARK: Folien

    /// Lädt neue Folien aller verknüpften Module.
    func syncNow(modules onlyModules: [StudyModule]? = nil) async {
        guard let credentials = store.load() else {
            errorMessage = StudIPError.notConnected.localizedDescription
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let modules = try onlyModules ?? moduleRepository.all()
            var summary = try await syncCourses(modules: modules, credentials: credentials)
            try await addAnnouncements(to: &summary, modules: modules, credentials: credentials)
            if onlyModules == nil {
                try await importTimetable(into: &summary, modules: modules, credentials: credentials)
                lastSync = now()
                store.lastSlideSync = lastSync
            }
            if summary.hasChanges {
                slidesRevision += 1
                onSlidesChanged?()
            }
            report(summary)
        } catch {
            noteSessionExpiry(error)
            errorMessage = "Stud.IP: \(error.localizedDescription)"
        }
    }

    /// Beim Start und regelmäßig: still im Hintergrund, Meldung nur bei neuen Folien.
    func syncIfDue() async {
        guard store.autoSyncSlides, store.load() != nil, !isSyncing, !sessionExpired else { return }
        if let lastSync, now().timeIntervalSince(lastSync) < Self.autoSyncInterval { return }
        guard let credentials = store.load(),
              let modules = try? moduleRepository.all(),
              modules.contains(where: { $0.studIPCourseID != nil && !$0.isArchived }) else { return }
        isSyncing = true
        defer { isSyncing = false }
        // Auch ein fehlgeschlagener Versuch zählt, sonst würde ohne Netz ständig neu versucht.
        lastSync = now()
        store.lastSlideSync = lastSync
        var summary: StudIPSyncSummary
        do {
            summary = try await syncCourses(modules: modules, credentials: credentials)
            try await addAnnouncements(to: &summary, modules: modules, credentials: credentials)
            try await importTimetable(into: &summary, modules: modules, credentials: credentials)
        } catch {
            // Im Hintergrund still bleiben; die Einstellungen zeigen „Sitzung abgelaufen“.
            noteSessionExpiry(error)
            return
        }
        guard summary.hasChanges || !summary.newAnnouncements.isEmpty else { return }
        if summary.hasChanges {
            slidesRevision += 1
            onSlidesChanged?()
        }
        onBackgroundSyncChanges?(summary)
        report(summary)
    }

    /// Announcements are synced after the files; a module that fails only adds to the failures.
    private func addAnnouncements(
        to summary: inout StudIPSyncSummary,
        modules: [StudyModule],
        credentials: StudIPCredentials
    ) async throws {
        guard let syncAnnouncements else { return }
        let result = try await syncAnnouncements(modules: modules, credentials: credentials)
        summary.newAnnouncements = result.new
        summary.failures += result.failures
        onAnnouncementsSynced?()
    }

    /// Imports the dates of linked courses when the setting is on; failing modules only add to the failures.
    private func importTimetable(
        into summary: inout StudIPSyncSummary,
        modules: [StudyModule],
        credentials: StudIPCredentials
    ) async throws {
        guard let syncTimetable, settings?.importsStudIPTimetable == true else { return }
        summary.failures += try await syncTimetable(modules: modules, credentials: credentials)
        onTimetableSynced?()
    }

    private func noteSessionExpiry(_ error: any Error) {
        if (error as? StudIPError) == .sessionExpired { sessionExpired = true }
    }

    private func report(_ summary: StudIPSyncSummary) {
        if !summary.failures.isEmpty, !summary.hasChanges {
            errorMessage = "Nicht alle Dateien konnten geladen werden:\n" + summary.failures.prefix(5).joined(separator: "\n")
            return
        }
        announce(Self.summaryText(summary))
    }

    static func summaryText(_ summary: StudIPSyncSummary) -> String {
        if summary.checkedModules == 0 {
            return "Noch kein Modul ist mit einer Stud.IP-Veranstaltung verknüpft."
        }
        guard summary.hasChanges || !summary.newAnnouncements.isEmpty else { return "Stud.IP: keine neuen Dateien." }
        var parts: [String] = []
        if !summary.imported.isEmpty {
            parts.append(summary.imported.count == 1 ? "1 neuer Foliensatz" : "\(summary.imported.count) neue Foliensätze")
        }
        if !summary.updated.isEmpty {
            parts.append(summary.updated.count == 1 ? "1 aktualisierter" : "\(summary.updated.count) aktualisierte")
        }
        if !summary.downloadedFiles.isEmpty {
            parts.append(summary.downloadedFiles.count == 1 ? "1 Datei geladen" : "\(summary.downloadedFiles.count) Dateien geladen")
        }
        if !summary.newAnnouncements.isEmpty {
            parts.append(summary.newAnnouncements.count == 1 ? "1 neue Ankündigung" : "\(summary.newAnnouncements.count) neue Ankündigungen")
        }
        var text = "Stud.IP: " + parts.joined(separator: ", ")
        if !summary.failures.isEmpty { text += " · \(summary.failures.count) Fehler" }
        return text
    }

    private func announce(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    private static func newestFirst(_ lhs: StudIPCourse, _ rhs: StudIPCourse) -> Bool {
        switch (lhs.semester, rhs.semester) {
        case let (left?, right?) where left != right: left > right
        case (_?, nil): true
        case (nil, _?): false
        default: lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
