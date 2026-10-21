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
    /// Erhöht sich nach jedem Abgleich mit neuen Folien oder Dateien, damit offene Module ihre Listen neu laden.
    private(set) var slidesRevision = 0
    var errorMessage: String?

    var autoSyncSlides = true {
        didSet { store.autoSyncSlides = autoSyncSlides }
    }

    var isConnected: Bool { account != nil }

    /// Wird nach geladenen Folien aufgerufen, z. B. um Zähler auf der Startseite zu aktualisieren.
    @ObservationIgnored var onSlidesChanged: (() -> Void)?

    private let store: any StudIPAccountStore
    private let moduleRepository: any ModuleRepository
    private let connectUseCase: ConnectStudIPUseCase
    private let linkCourse: LinkStudIPCourseUseCase
    private let syncCourses: SyncStudIPCoursesUseCase
    private let service: any StudIPService
    private let now: () -> Date
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    init(
        service: any StudIPService,
        store: any StudIPAccountStore,
        moduleRepository: any ModuleRepository,
        slideRepository: any SlideDocumentRepository,
        importer: ImportSlideDocumentUseCase,
        fileRepository: (any CourseFileRepository)? = nil,
        storage: (any FileStorage)? = nil,
        now: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.store = store
        self.moduleRepository = moduleRepository
        self.now = now
        connectUseCase = ConnectStudIPUseCase(service: service, store: store)
        var removeFiles: RemoveCourseFilesUseCase?
        if let fileRepository, let storage {
            removeFiles = RemoveCourseFilesUseCase(repository: fileRepository, storage: storage)
        }
        linkCourse = LinkStudIPCourseUseCase(repository: moduleRepository, removeFiles: removeFiles)
        syncCourses = SyncStudIPCoursesUseCase(
            slideRepository: slideRepository, service: service, importer: importer,
            fileRepository: fileRepository, storage: storage
        )
        account = store.load()?.account
        lastSync = store.lastSlideSync
        autoSyncSlides = store.autoSyncSlides
    }

    // MARK: Anmeldung

    /// Fehler werden geworfen, damit das Formular sie direkt anzeigen kann.
    func connect(server: String, username: String, password: String) async throws {
        let name = try await connectUseCase(server: server, username: username, password: password)
        account = store.load()?.account
        courses = []
        announce("Mit Stud.IP verbunden als \(name).")
    }

    func disconnect() {
        store.delete()
        account = nil
        courses = []
        lastSync = nil
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
            let summary = try await syncCourses(modules: modules, credentials: credentials)
            if onlyModules == nil {
                lastSync = now()
                store.lastSlideSync = lastSync
            }
            if summary.hasChanges {
                slidesRevision += 1
                onSlidesChanged?()
            }
            report(summary)
        } catch {
            errorMessage = "Stud.IP: \(error.localizedDescription)"
        }
    }

    /// Beim Start und regelmäßig: still im Hintergrund, Meldung nur bei neuen Folien.
    func syncIfDue() async {
        guard store.autoSyncSlides, store.load() != nil, !isSyncing else { return }
        if let lastSync, now().timeIntervalSince(lastSync) < Self.autoSyncInterval { return }
        guard let credentials = store.load(),
              let modules = try? moduleRepository.all(),
              modules.contains(where: { $0.studIPCourseID != nil && !$0.isArchived }) else { return }
        isSyncing = true
        defer { isSyncing = false }
        // Auch ein fehlgeschlagener Versuch zählt, sonst würde ohne Netz ständig neu versucht.
        lastSync = now()
        store.lastSlideSync = lastSync
        guard let summary = try? await syncCourses(modules: modules, credentials: credentials),
              summary.hasChanges else { return }
        slidesRevision += 1
        onSlidesChanged?()
        report(summary)
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
        guard summary.hasChanges else { return "Stud.IP: keine neuen Dateien." }
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
