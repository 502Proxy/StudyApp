import Foundation
import Observation

typealias CourseFilesViewModelFactory = @MainActor (StudyModule) -> CourseFilesViewModel

/// Dateibereich eines Moduls: Stud.IP-Dateien nach Ordnern, mit Download auf Klick.
@MainActor
@Observable
final class CourseFilesViewModel {
    struct Folder: Identifiable, Equatable {
        /// Leer für den Hauptordner.
        let path: String
        let files: [CourseFile]
        var id: String { path }
        var title: String { path.isEmpty ? "Hauptordner" : path }
    }

    /// Was beim Öffnen einer Datei passieren soll.
    enum OpenAction: Equatable {
        /// PDF, das schon als Foliensatz importiert ist.
        case slides(documentID: UUID)
        /// Lokale Kopie in der passenden App öffnen.
        case file(URL)
    }

    let module: StudyModule
    private(set) var files: [CourseFile] = []
    private(set) var downloading: Set<String> = []
    var searchText = ""
    var errorMessage: String?

    private let repository: any CourseFileRepository
    private let slideRepository: any SlideDocumentRepository
    private let storage: any FileStorage
    private let store: any StudIPAccountStore
    private let download: DownloadCourseFileUseCase

    init(
        module: StudyModule,
        repository: any CourseFileRepository,
        slideRepository: any SlideDocumentRepository,
        service: any StudIPService,
        storage: any FileStorage,
        store: any StudIPAccountStore
    ) {
        self.module = module
        self.repository = repository
        self.slideRepository = slideRepository
        self.storage = storage
        self.store = store
        download = DownloadCourseFileUseCase(repository: repository, service: service, storage: storage)
    }

    var isConnected: Bool { store.load() != nil }
    var downloadedCount: Int { files.filter(\.isDownloaded).count }

    /// Gefilterte Dateien nach Ordnern, Hauptordner zuerst, sonst alphabetisch.
    var folders: [Folder] {
        let query = searchText.trimmed
        let visible = query.isEmpty ? files : files.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.folderPath.localizedCaseInsensitiveContains(query)
        }
        return Dictionary(grouping: visible, by: \.folderPath)
            .map { path, files in
                Folder(path: path, files: files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
            .sorted { lhs, rhs in
                if lhs.path.isEmpty != rhs.path.isEmpty { return lhs.path.isEmpty }
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
    }

    func load() {
        do {
            files = try repository.files(forModule: module.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func localURL(of file: CourseFile) -> URL? {
        file.localFileName.map(storage.url(for:))
    }

    /// PDFs öffnen als Folien, alles andere als lokale Kopie – fehlt sie, wird sie zuerst geladen.
    func openAction(for file: CourseFile) async -> OpenAction? {
        if file.isPDF, let document = slideDocument(for: file) {
            return .slides(documentID: document.id)
        }
        if let url = localURL(of: file), !file.isOutdated {
            return .file(url)
        }
        guard let updated = await fetch(file) else { return nil }
        return localURL(of: updated).map(OpenAction.file)
    }

    /// Lädt eine Datei (neu) herunter.
    @discardableResult
    func fetch(_ file: CourseFile) async -> CourseFile? {
        guard let credentials = store.load() else {
            errorMessage = StudIPError.notConnected.localizedDescription
            return nil
        }
        guard downloading.insert(file.id).inserted else { return nil }
        defer { downloading.remove(file.id) }
        do {
            let updated = try await download(file, credentials)
            load()
            return updated
        } catch {
            errorMessage = "„\(file.name)“ konnte nicht geladen werden: \(error.localizedDescription)"
            return nil
        }
    }

    private func slideDocument(for file: CourseFile) -> SlideDocument? {
        let documents = (try? slideRepository.documents(forModule: module.id)) ?? []
        return SyncStudIPCoursesUseCase.latestDocuments(documents)[file.remoteID]
    }
}
