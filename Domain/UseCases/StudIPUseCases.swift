import Foundation

/// Normalisiert die eingegebene Stud.IP-Adresse auf die Basis der Installation.
/// Akzeptiert auch kopierte Links wie `elearning.uni-oldenburg.de/dispatch.php/start`.
enum StudIPServerURL {
    /// Pfadteile, ab denen eine Adresse nicht mehr zur Basis gehört.
    private static let entryPoints = ["dispatch.php", "jsonapi.php", "api.php", "index.php", "plugins.php", "seminar_main.php"]

    static func normalized(_ input: String) throws -> URL {
        var text = input.trimmed
        guard !text.isEmpty else { throw StudIPError.invalidServerURL }
        if !text.contains("://") { text = "https://" + text }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, host.contains(".") else {
            throw StudIPError.invalidServerURL
        }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        var parts = components.path.split(separator: "/").map(String.init)
        if let index = parts.firstIndex(where: { entryPoints.contains($0.lowercased()) }) {
            parts = Array(parts[..<index])
        }
        components.path = parts.isEmpty ? "" : "/" + parts.joined(separator: "/")
        guard let url = components.url else { throw StudIPError.invalidServerURL }
        return url
    }
}

/// Prüft die Anmeldung und speichert sie erst danach.
@MainActor
struct ConnectStudIPUseCase {
    let service: any StudIPService
    let store: any StudIPAccountStore

    /// - Returns: Anzeigename der angemeldeten Person.
    @discardableResult
    func callAsFunction(server: String, username: String, password: String) async throws -> String {
        let account = StudIPAccount(serverURL: try StudIPServerURL.normalized(server), username: username.trimmed)
        guard !account.username.isEmpty, !password.isEmpty else { throw StudIPError.unauthorized }
        let credentials = StudIPCredentials(account: account, password: password)
        let name = try await service.verify(credentials)
        try store.save(credentials)
        return name
    }
}

/// Ordnet Module den Stud.IP-Veranstaltungen zu, aus denen ihre Folien kommen.
@MainActor
struct LinkStudIPCourseUseCase {
    let repository: any ModuleRepository
    /// Beim Wechsel der Veranstaltung gehören die bisher geladenen Dateien nicht mehr zum Modul.
    var removeFiles: RemoveCourseFilesUseCase? = nil

    @discardableResult
    func callAsFunction(_ module: StudyModule, courseID: String?) throws -> StudyModule {
        guard module.studIPCourseID != courseID else { return module }
        var updated = module
        updated.studIPCourseID = courseID
        try repository.update(updated)
        if module.studIPCourseID != nil {
            try removeFiles?(moduleID: module.id)
        }
        return updated
    }
}

/// Schlägt zu einem Modul die passende Stud.IP-Veranstaltung vor (über Kürzel, Titel und Semester).
enum StudIPCourseMatcher {
    static func bestCourse(for module: StudyModule, in courses: [StudIPCourse]) -> StudIPCourse? {
        let moduleKey = key(module.name)
        let moduleCode = CourseTitleAnalyzer.makeKey(module.code)
        var best: (course: StudIPCourse, score: Int)?
        for course in courses {
            var score = titleScore(moduleKey, key(course.title))
            if !moduleCode.isEmpty {
                let number = CourseTitleAnalyzer.makeKey(course.number)
                if number == moduleCode || key(course.title).split(separator: " ").contains(Substring(moduleCode)) {
                    score = max(score, 3)
                }
            }
            guard score > 0 else { continue }
            // Bei gleichnamigen Veranstaltungen mehrerer Semester gewinnt die des Modulsemesters.
            if course.semester == module.semester { score += 1 }
            if score > (best?.score ?? 0) { best = (course, score) }
        }
        return best?.course
    }

    /// 3: gleicher Titel, 2: ein Titel enthält den anderen, 1: überwiegend gleiche Wörter.
    static func titleScore(_ lhs: String, _ rhs: String) -> Int {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        if lhs == rhs { return 3 }
        if min(lhs.count, rhs.count) >= 4, lhs.contains(rhs) || rhs.contains(lhs) { return 2 }
        let left = Set(lhs.split(separator: " ")), right = Set(rhs.split(separator: " "))
        let overlap = Double(left.intersection(right).count) / Double(max(left.union(right).count, 1))
        return overlap >= 0.6 ? 1 : 0
    }

    private static func key(_ title: String) -> String {
        CourseTitleAnalyzer.analyze(title)?.key ?? CourseTitleAnalyzer.makeKey(title)
    }
}

struct StudIPSyncSummary: Equatable, Sendable {
    /// Titel neu geladener Foliensätze.
    var imported: [String] = []
    /// Titel, von denen eine neue Fassung geladen wurde.
    var updated: [String] = []
    /// Namen heruntergeladener Dateien (ohne PDFs, die als Folien zählen).
    var downloadedFiles: [String] = []
    /// Fehler einzelner Module oder Dateien; der Abgleich der übrigen läuft weiter.
    var failures: [String] = []
    var checkedModules = 0

    var newDocumentCount: Int { imported.count + updated.count }
    var hasChanges: Bool { newDocumentCount > 0 || !downloadedFiles.isEmpty }
}

/// Gleicht die verknüpften Stud.IP-Veranstaltungen ab:
/// - PDFs werden zu Foliensätzen. Bekannte Dateien werden übersprungen; ändert sich eine Datei in Stud.IP,
///   kommt die neue Fassung als zusätzlicher Foliensatz dazu, damit Markierungen und Notizen der alten bleiben.
/// - Alle Dateien landen im Dateikatalog des Moduls; alles außer PDFs wird bis `autoDownloadLimit` heruntergeladen.
@MainActor
struct SyncStudIPCoursesUseCase {
    /// Größere Dateien (z. B. Videos) lädt man bei Bedarf von Hand.
    static let defaultAutoDownloadLimit = 50 * 1_024 * 1_024

    let slideRepository: any SlideDocumentRepository
    let service: any StudIPService
    let importer: ImportSlideDocumentUseCase
    var fileRepository: (any CourseFileRepository)? = nil
    var storage: (any FileStorage)? = nil
    var autoDownloadLimit = Self.defaultAutoDownloadLimit

    func callAsFunction(modules: [StudyModule], credentials: StudIPCredentials) async throws -> StudIPSyncSummary {
        var summary = StudIPSyncSummary()
        for module in modules where !module.isArchived {
            guard let courseID = module.studIPCourseID else { continue }
            summary.checkedModules += 1
            let files: [StudIPFile]
            do {
                files = try await service.files(inCourse: courseID, credentials)
            } catch let error as StudIPError where Self.isFatal(error) {
                throw error
            } catch {
                summary.failures.append("\(module.name): \(error.localizedDescription)")
                continue
            }
            try await importSlides(from: files, into: module, credentials, &summary)
            try await updateCatalog(with: files, of: module, credentials, &summary)
        }
        return summary
    }

    private func importSlides(
        from files: [StudIPFile], into module: StudyModule, _ credentials: StudIPCredentials, _ summary: inout StudIPSyncSummary
    ) async throws {
        let latest = Self.latestDocuments(try slideRepository.documents(forModule: module.id))
        for file in files where file.isPDF {
            let known = latest[file.id]
            if let known, known.remoteVersion == file.version { continue }
            do {
                let data = try await service.download(file, credentials)
                let baseTitle = Self.title(for: file)
                let title = known == nil ? baseTitle : "\(baseTitle) (aktualisiert)"
                try importer(data: data, title: title, moduleID: module.id, remoteID: file.id, remoteVersion: file.version)
                if known == nil {
                    summary.imported.append(title)
                } else {
                    summary.updated.append(title)
                }
            } catch let error as StudIPError where Self.isFatal(error) {
                throw error
            } catch {
                summary.failures.append("\(file.name): \(error.localizedDescription)")
            }
        }
    }

    private func updateCatalog(
        with files: [StudIPFile], of module: StudyModule, _ credentials: StudIPCredentials, _ summary: inout StudIPSyncSummary
    ) async throws {
        guard let fileRepository, let storage else { return }
        let removed = try fileRepository.replaceCatalog(forModule: module.id, with: files.map { CourseFile($0, moduleID: module.id) })
        for file in removed {
            if let local = file.localFileName { try? storage.remove(fileName: local) }
        }
        let download = DownloadCourseFileUseCase(repository: fileRepository, service: service, storage: storage)
        for file in try fileRepository.files(forModule: module.id) where Self.shouldDownload(file, limit: autoDownloadLimit) {
            do {
                try await download(file, credentials)
                summary.downloadedFiles.append(file.name)
            } catch let error as StudIPError where Self.isFatal(error) {
                throw error
            } catch {
                summary.failures.append("\(file.name): \(error.localizedDescription)")
            }
        }
    }

    /// PDFs kommen über die Folien; alles andere, wenn es fehlt oder veraltet ist und nicht zu groß.
    static func shouldDownload(_ file: CourseFile, limit: Int) -> Bool {
        guard !file.isPDF, !file.isDownloaded || file.isOutdated else { return false }
        return (file.size ?? 0) <= limit
    }

    /// Ohne Netz oder mit ungültiger Anmeldung lohnt sich kein weiterer Versuch.
    static func isFatal(_ error: StudIPError) -> Bool {
        error == .unauthorized || error == .offline
    }

    /// Je Stud.IP-Datei der zuletzt geladene Foliensatz.
    static func latestDocuments(_ documents: [SlideDocument]) -> [String: SlideDocument] {
        var result: [String: SlideDocument] = [:]
        for document in documents {
            guard let remoteID = document.remoteID else { continue }
            if let existing = result[remoteID], existing.importedAt >= document.importedAt { continue }
            result[remoteID] = document
        }
        return result
    }

    static func title(for file: StudIPFile) -> String {
        let name = file.name.trimmed
        return name.lowercased().hasSuffix(".pdf") ? String(name.dropLast(4)) : name
    }
}

/// Lädt eine einzelne Datei (neu) herunter, z. B. auf Klick oder wenn es eine neue Fassung gibt.
@MainActor
struct DownloadCourseFileUseCase {
    let repository: any CourseFileRepository
    let service: any StudIPService
    let storage: any FileStorage

    @discardableResult
    func callAsFunction(_ file: CourseFile, _ credentials: StudIPCredentials) async throws -> CourseFile {
        let remote = StudIPFile(id: file.remoteID, name: file.name, size: file.size, version: file.version, mimeType: file.mimeType)
        let data = try await service.download(remote, credentials)
        let fileName = Self.storagePath(for: file)
        try storage.write(data, as: fileName)
        if let previous = file.localFileName, previous != fileName {
            try? storage.remove(fileName: previous)
        }
        var updated = file
        updated.localFileName = fileName
        updated.downloadedVersion = file.version
        try repository.update(updated)
        return updated
    }

    /// Eigener Ordner je Datei, damit der Originalname erhalten bleibt und sich nichts überschreibt.
    static func storagePath(for file: CourseFile) -> String {
        let cleaned = file.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmed
        let name = cleaned.isEmpty || cleaned.hasPrefix(".") ? "Datei\(cleaned)" : cleaned
        return "StudIP/\(file.moduleID.uuidString)/\(file.remoteID)/\(name)"
    }
}

/// Entfernt Katalog und heruntergeladene Dateien eines Moduls.
@MainActor
struct RemoveCourseFilesUseCase {
    let repository: any CourseFileRepository
    let storage: any FileStorage

    func callAsFunction(moduleID: UUID) throws {
        for file in try repository.deleteFiles(forModule: moduleID) {
            if let local = file.localFileName { try? storage.remove(fileName: local) }
        }
    }
}
