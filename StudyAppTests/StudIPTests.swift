import Foundation
import Testing
@testable import StudyApp

// MARK: Testdoubles

@MainActor
final class FakeStudIPService: StudIPService {
    var userName = "Tristan Müller"
    var acceptedPassword = "geheim"
    var coursesResult: [StudIPCourse] = []
    var filesByCourse: [String: [StudIPFile]] = [:]
    var failingCourses: [String: StudIPError] = [:]
    var downloadError: StudIPError?
    private(set) var downloads: [String] = []

    /// Cookie-Header einer angemeldeten Browser-Sitzung.
    var acceptedSession = "Seminar_Session=angemeldet"
    var failure: StudIPError?

    func verify(_ credentials: StudIPCredentials) async throws -> StudIPUser {
        switch credentials.authorization {
        case .password(let password):
            guard password == acceptedPassword else { throw StudIPError.unauthorized }
        case .session(let cookieHeader):
            guard cookieHeader == acceptedSession else { throw StudIPError.sessionExpired }
        }
        return StudIPUser(username: "tmueller13", displayName: userName)
    }

    func courses(_ credentials: StudIPCredentials) async throws -> [StudIPCourse] { coursesResult }

    func files(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPFile] {
        if let failure { throw failure }
        if let error = failingCourses[courseID] { throw error }
        return filesByCourse[courseID] ?? []
    }

    func download(_ file: StudIPFile, _ credentials: StudIPCredentials) async throws -> Data {
        if let downloadError { throw downloadError }
        downloads.append(file.id)
        return Data("%PDF-\(file.id)".utf8)
    }
}

private let credentials = StudIPCredentials(
    account: StudIPAccount(serverURL: URL(string: "https://elearning.uni-oldenburg.de")!, username: "abcd1234"),
    password: "geheim"
)

private func pdf(_ id: String, _ name: String, version: String = "1") -> StudIPFile {
    StudIPFile(id: id, name: name, size: 1_000, version: version, mimeType: "application/pdf")
}

// MARK: Adresse und Zuordnung

@MainActor
struct StudIPServerURLTests {
    @Test(arguments: [
        ("elearning.uni-oldenburg.de", "https://elearning.uni-oldenburg.de"),
        ("https://elearning.uni-oldenburg.de/", "https://elearning.uni-oldenburg.de"),
        ("https://elearning.uni-oldenburg.de/dispatch.php/start?cid=1", "https://elearning.uni-oldenburg.de"),
        ("https://uni.example.org/studip/jsonapi.php/v1/users/me", "https://uni.example.org/studip"),
        ("  HTTPS://studip.example.org/studip/index.php  ", "https://studip.example.org/studip"),
    ])
    func normalizesToInstallationBase(input: String, expected: String) throws {
        #expect(try StudIPServerURL.normalized(input).absoluteString == expected)
    }

    @Test(arguments: ["", "ftp://studip.example.org", "localhost", "https://"])
    func rejectsInvalidAddresses(input: String) {
        #expect(throws: StudIPError.invalidServerURL) { try StudIPServerURL.normalized(input) }
    }
}

@MainActor
struct StudIPCourseMatcherTests {
    private let winter = Semester(term: .winter, year: 2025)

    private func module(_ name: String, code: String = "") -> StudyModule {
        StudyModule(id: UUID(), name: name, code: code, color: .blue, createdAt: Date(), semester: winter)
    }

    @Test func prefersExactTitleOfTheModuleSemester() {
        let courses = [
            StudIPCourse(id: "old", title: "Analysis I", number: "", semesterTitle: "WiSe 2024/25"),
            StudIPCourse(id: "new", title: "Analysis I", number: "", semesterTitle: "WiSe 2025/26"),
            StudIPCourse(id: "other", title: "Lineare Algebra", number: "", semesterTitle: "WiSe 2025/26"),
        ]
        #expect(StudIPCourseMatcher.bestCourse(for: module("Analysis I"), in: courses)?.id == "new")
    }

    @Test func matchesByCourseNumberOrContainedTitle() {
        let courses = [
            StudIPCourse(id: "pda", title: "Programmierung, Datenstrukturen und Algorithmen", number: "inf030", semesterTitle: nil),
            StudIPCourse(id: "stats", title: "Vorlesung: Statistik für Wirtschaftswissenschaften", number: "", semesterTitle: nil),
        ]
        #expect(StudIPCourseMatcher.bestCourse(for: module("PDA", code: "INF030"), in: courses)?.id == "pda")
        #expect(StudIPCourseMatcher.bestCourse(for: module("Statistik"), in: courses)?.id == "stats")
    }

    @Test func returnsNothingWithoutAPlausibleMatch() {
        let courses = [StudIPCourse(id: "x", title: "Einführung in die Philosophie", number: "", semesterTitle: nil)]
        #expect(StudIPCourseMatcher.bestCourse(for: module("Analysis I"), in: courses) == nil)
    }
}

// MARK: JSON:API

@MainActor
struct StudIPJSONAPIParserTests {
    private func json(_ text: String) -> Data { Data(text.utf8) }

    @Test func readsCurrentUser() throws {
        let user = try StudIPJSONAPIParser.currentUser(json("""
        {"data": {"type": "users", "id": "u1", "attributes": {"username": "abcd1234", "formatted-name": "Tristan Müller"}}}
        """))
        #expect(user.id == "u1")
        #expect(user.user == StudIPUser(username: "abcd1234", displayName: "Tristan Müller"))
    }

    @Test func readsCoursesWithSemesterAndNextLink() throws {
        let semesters = try StudIPJSONAPIParser.page(json("""
        {"data": [{"type": "semesters", "id": "s1", "attributes": {"title": "WiSe 2025/26"}}]}
        """))
        let titles = StudIPJSONAPIParser.semesterTitles(semesters.resources)
        let page = try StudIPJSONAPIParser.page(json("""
        {"data": [
            {"type": "courses", "id": "c1", "attributes": {"title": "Analysis I", "course-number": "mat101"},
             "relationships": {"start-semester": {"data": {"type": "semesters", "id": "s1"}}}},
            {"type": "courses", "id": "c2", "attributes": {}}
        ],
         "links": {"next": "/jsonapi.php/v1/users/u1/courses?page[offset]=100"}}
        """))
        let courses = page.resources.compactMap { StudIPJSONAPIParser.course($0, semesterTitles: titles) }

        #expect(courses == [StudIPCourse(id: "c1", title: "Analysis I", number: "mat101", semesterTitle: "WiSe 2025/26")])
        #expect(courses.first?.semester == Semester(term: .winter, year: 2025))
        #expect(page.next == "/jsonapi.php/v1/users/u1/courses?page[offset]=100")
    }

    @Test func readsFilesWithNumericOrTextualDates() throws {
        let page = try StudIPJSONAPIParser.page(json("""
        {"data": [
            {"type": "file-refs", "id": "f1", "attributes": {"name": "VL01.pdf", "filesize": 2048, "chdate": "2025-10-20T10:00:00+02:00", "mime-type": "application/pdf"}},
            {"type": "file-refs", "id": "f2", "attributes": {"name": "Blatt 1.docx", "filesize": "512", "mkdate": 1760000000}}
        ]}
        """))
        let files = page.resources.compactMap(StudIPJSONAPIParser.file)

        #expect(files.count == 2)
        #expect(files[0].isPDF)
        #expect(files[0].size == 2048)
        #expect(files[0].version == "2025-10-20T10:00:00+02:00")
        #expect(!files[1].isPDF)
        #expect(files[1].size == 512)
        #expect(files[1].version == "1760000000")
    }

    @Test func htmlLoginPageIsAnInvalidResponse() {
        #expect(throws: StudIPError.invalidResponse) {
            try StudIPJSONAPIParser.page(json("<html><body>Login</body></html>"))
        }
    }
}

// MARK: Abgleich

@MainActor
struct SyncStudIPCoursesTests {
    let slides = FakeSlideDocumentRepository()
    let storage = FakeFileStorage()
    let service = FakeStudIPService()

    private var sync: SyncStudIPCoursesUseCase {
        SyncStudIPCoursesUseCase(
            slideRepository: slides,
            service: service,
            importer: ImportSlideDocumentUseCase(repository: slides, storage: storage, inspector: FakeInspector(pages: 12))
        )
    }

    private func module(course: String?, archived: Bool = false) -> StudyModule {
        StudyModule(id: UUID(), name: "Analysis", code: "", color: .blue, createdAt: Date(), isArchived: archived, studIPCourseID: course)
    }

    @Test func importsNewPDFsOnceAndSkipsOtherFiles() async throws {
        let analysis = module(course: "c1")
        service.filesByCourse["c1"] = [
            pdf("f1", "VL01 Grenzwerte.pdf"),
            StudIPFile(id: "f2", name: "Übungsblatt.docx", size: nil, version: "1", mimeType: nil),
        ]

        let first = try await sync(modules: [analysis, module(course: nil)], credentials: credentials)
        let second = try await sync(modules: [analysis], credentials: credentials)

        #expect(first.imported == ["VL01 Grenzwerte"])
        #expect(first.checkedModules == 1)
        #expect(second.newDocumentCount == 0)
        #expect(service.downloads == ["f1"])
        let document = try #require(slides.storage.first)
        #expect(document.moduleID == analysis.id)
        #expect(document.remoteID == "f1")
        #expect(document.pageCount == 12)
        #expect(storage.written[document.fileName] == Data("%PDF-f1".utf8))
    }

    @Test func changedFileComesInAsAdditionalDocument() async throws {
        let analysis = module(course: "c1")
        service.filesByCourse["c1"] = [pdf("f1", "VL01.pdf", version: "1")]
        _ = try await sync(modules: [analysis], credentials: credentials)

        service.filesByCourse["c1"] = [pdf("f1", "VL01.pdf", version: "2")]
        let summary = try await sync(modules: [analysis], credentials: credentials)
        let again = try await sync(modules: [analysis], credentials: credentials)

        #expect(summary.updated == ["VL01 (aktualisiert)"])
        #expect(again.newDocumentCount == 0)
        // Die alte Fassung mit ihren Markierungen bleibt erhalten.
        #expect(slides.storage.map(\.title).sorted() == ["VL01", "VL01 (aktualisiert)"])
    }

    @Test func archivedModulesAreSkipped() async throws {
        service.filesByCourse["c1"] = [pdf("f1", "VL01.pdf")]
        let summary = try await sync(modules: [module(course: "c1", archived: true)], credentials: credentials)
        #expect(summary.checkedModules == 0)
        #expect(slides.storage.isEmpty)
    }

    @Test func oneBrokenCourseDoesNotStopTheOthers() async throws {
        service.failingCourses["broken"] = .server(statusCode: 403)
        service.filesByCourse["c1"] = [pdf("f1", "VL01.pdf")]

        let summary = try await sync(modules: [module(course: "broken"), module(course: "c1")], credentials: credentials)

        #expect(summary.imported == ["VL01"])
        #expect(summary.failures.count == 1)
    }

    @Test func rejectedLoginAbortsTheWholeSync() async {
        service.failingCourses["c1"] = .unauthorized
        await #expect(throws: StudIPError.unauthorized) {
            try await sync(modules: [module(course: "c1")], credentials: credentials)
        }
    }

    @Test func unreadablePDFIsReportedAndCleanedUp() async throws {
        let broken = SyncStudIPCoursesUseCase(
            slideRepository: slides,
            service: service,
            importer: ImportSlideDocumentUseCase(repository: slides, storage: storage, inspector: FakeInspector(pages: nil))
        )
        service.filesByCourse["c1"] = [pdf("f1", "Kaputt.pdf")]

        let summary = try await broken(modules: [module(course: "c1")], credentials: credentials)

        #expect(summary.failures.count == 1)
        #expect(slides.storage.isEmpty)
        #expect(storage.files.isEmpty)
    }
}

// MARK: ViewModel

@MainActor
struct StudIPViewModelTests {
    let service = FakeStudIPService()
    let store = InMemoryStudIPAccountStore()
    let modules = FakeModuleRepository()
    let slides = FakeSlideDocumentRepository()
    var clock = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeViewModel(now: Date) -> StudIPViewModel {
        StudIPViewModel(
            service: service,
            store: store,
            moduleRepository: modules,
            slideRepository: slides,
            importer: ImportSlideDocumentUseCase(repository: slides, storage: FakeFileStorage(), inspector: FakeInspector(pages: 3)),
            now: { now }
        )
    }

    @Test func refreshMarksAnExpiredSessionAndAReconnectClearsIt() async throws {
        let viewModel = makeViewModel(now: clock)
        let server = URL(string: "https://elearning.uni-oldenburg.de")!
        try store.save(StudIPCredentials(
            account: StudIPAccount(serverURL: server, username: "abcd1234"),
            authorization: .session(cookieHeader: "Seminar_Session=abgelaufen")
        ))

        await viewModel.refreshSessionState()
        #expect(viewModel.sessionExpired)

        #expect(await viewModel.connect(server: server, cookieHeader: service.acceptedSession))
        #expect(!viewModel.sessionExpired)
        await viewModel.refreshSessionState()
        #expect(!viewModel.sessionExpired)
    }

    @Test func connectStoresCredentialsOnlyAfterSuccessfulLogin() async throws {
        let viewModel = makeViewModel(now: clock)

        await #expect(throws: StudIPError.unauthorized) {
            try await viewModel.connect(server: "elearning.uni-oldenburg.de", username: "abcd1234", password: "falsch")
        }
        #expect(store.credentials == nil)
        #expect(!viewModel.isConnected)

        try await viewModel.connect(server: "elearning.uni-oldenburg.de", username: " abcd1234 ", password: "geheim")
        #expect(store.credentials == credentials)
        #expect(viewModel.account?.username == "abcd1234")

        viewModel.disconnect()
        #expect(store.credentials == nil)
        #expect(!viewModel.isConnected)
    }

    @Test func automaticSyncRunsAtMostEveryFewHours() async throws {
        store.credentials = credentials
        let module = StudyModule(id: UUID(), name: "Analysis", code: "", color: .blue, createdAt: clock, studIPCourseID: "c1")
        modules.storage = [module]
        service.filesByCourse["c1"] = [pdf("f1", "VL01.pdf")]

        let viewModel = makeViewModel(now: clock)
        await viewModel.syncIfDue()
        #expect(slides.storage.count == 1)
        #expect(viewModel.slidesRevision == 1)

        service.filesByCourse["c1"]?.append(pdf("f2", "VL02.pdf"))
        await viewModel.syncIfDue()
        #expect(slides.storage.count == 1)

        let later = makeViewModel(now: clock.addingTimeInterval(StudIPViewModel.autoSyncInterval + 1))
        await later.syncIfDue()
        #expect(slides.storage.count == 2)
    }

    @Test func automaticSyncCanBeTurnedOff() async {
        store.credentials = credentials
        store.autoSyncSlides = false
        modules.storage = [StudyModule(id: UUID(), name: "Analysis", code: "", color: .blue, createdAt: clock, studIPCourseID: "c1")]
        service.filesByCourse["c1"] = [pdf("f1", "VL01.pdf")]

        await makeViewModel(now: clock).syncIfDue()

        #expect(slides.storage.isEmpty)
    }

    @Test func suggestionsLinkOnlyUnlinkedModules() async throws {
        store.credentials = credentials
        let analysis = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: clock)
        let linked = StudyModule(id: UUID(), name: "Lineare Algebra", code: "", color: .teal, createdAt: clock, studIPCourseID: "manual")
        modules.storage = [analysis, linked]
        service.coursesResult = [
            StudIPCourse(id: "c-ana", title: "Analysis I", number: "", semesterTitle: nil),
            StudIPCourse(id: "c-la", title: "Lineare Algebra", number: "", semesterTitle: nil),
        ]
        let viewModel = makeViewModel(now: clock)
        await viewModel.loadCourses()

        #expect(viewModel.applySuggestions(to: modules.storage) == 1)
        #expect(modules.storage.map(\.studIPCourseID) == ["c-ana", "manual"])
    }

    @Test func summaryTextIsReadable() {
        var summary = StudIPSyncSummary(imported: ["VL01", "VL02"], updated: ["VL00"], checkedModules: 2)
        #expect(StudIPViewModel.summaryText(summary) == "Stud.IP: 2 neue Foliensätze, 1 aktualisierter")
        summary = StudIPSyncSummary(checkedModules: 1)
        #expect(StudIPViewModel.summaryText(summary) == "Stud.IP: keine neuen Dateien.")
        #expect(StudIPViewModel.summaryText(StudIPSyncSummary()) == "Noch kein Modul ist mit einer Stud.IP-Veranstaltung verknüpft.")
    }
}

// MARK: Dateibereich

@MainActor
final class FakeCourseFileRepository: CourseFileRepository {
    var storage: [CourseFile] = []

    func files(forModule moduleID: UUID) throws -> [CourseFile] {
        storage.filter { $0.moduleID == moduleID }
    }

    func replaceCatalog(forModule moduleID: UUID, with files: [CourseFile]) throws -> [CourseFile] {
        let stored = storage.filter { $0.moduleID == moduleID }
        let incoming = Set(files.map(\.remoteID))
        let removed = stored.filter { !incoming.contains($0.remoteID) }
        var merged: [CourseFile] = []
        for file in files {
            var entry = file
            if let known = stored.first(where: { $0.remoteID == file.remoteID }) {
                entry.localFileName = known.localFileName
                entry.downloadedVersion = known.downloadedVersion
            }
            merged.append(entry)
        }
        storage = storage.filter { $0.moduleID != moduleID } + merged
        return removed
    }

    func update(_ file: CourseFile) throws {
        guard let index = storage.firstIndex(where: { $0.id == file.id }) else { return }
        storage[index] = file
    }

    func deleteFiles(forModule moduleID: UUID) throws -> [CourseFile] {
        let removed = storage.filter { $0.moduleID == moduleID }
        storage.removeAll { $0.moduleID == moduleID }
        return removed
    }
}

private func file(_ id: String, _ name: String, size: Int? = 1_000, version: String = "1", folder: String = "") -> StudIPFile {
    StudIPFile(id: id, name: name, size: size, version: version, mimeType: nil, folderPath: folder)
}

@MainActor
struct CourseFileSyncTests {
    let slides = FakeSlideDocumentRepository()
    let storage = FakeFileStorage()
    let service = FakeStudIPService()
    let catalog = FakeCourseFileRepository()

    private var sync: SyncStudIPCoursesUseCase {
        SyncStudIPCoursesUseCase(
            slideRepository: slides,
            service: service,
            importer: ImportSlideDocumentUseCase(repository: slides, storage: storage, inspector: FakeInspector(pages: 4)),
            fileRepository: catalog,
            storage: storage,
            autoDownloadLimit: 10_000
        )
    }

    private let module = StudyModule(id: UUID(), name: "Programmierung", code: "", color: .blue, createdAt: Date(), studIPCourseID: "c1")

    @Test func catalogsAllFilesAndDownloadsSmallNonPDFs() async throws {
        service.filesByCourse["c1"] = [
            file("f1", "VL01.pdf"),
            file("f2", "Blatt 1.zip", folder: "Übungen"),
            file("f3", "Aufzeichnung.mp4", size: 900_000_000, folder: "Videos"),
        ]

        let summary = try await sync(modules: [module], credentials: credentials)

        #expect(summary.imported == ["VL01"])
        #expect(summary.downloadedFiles == ["Blatt 1.zip"])
        #expect(summary.hasChanges)
        let files = try catalog.files(forModule: module.id)
        #expect(files.count == 3)
        let sheet = try #require(files.first { $0.remoteID == "f2" })
        #expect(sheet.folderPath == "Übungen")
        #expect(sheet.localFileName == "StudIP/\(module.id.uuidString)/f2/Blatt 1.zip")
        #expect(storage.written[sheet.localFileName!] == Data("%PDF-f2".utf8))
        // PDFs laufen über die Folien, große Videos nur auf Klick.
        #expect(files.first { $0.remoteID == "f1" }?.isDownloaded == false)
        #expect(files.first { $0.remoteID == "f3" }?.isDownloaded == false)
    }

    @Test func secondSyncDownloadsOnlyChangedFiles() async throws {
        service.filesByCourse["c1"] = [file("f2", "Blatt 1.zip")]
        _ = try await sync(modules: [module], credentials: credentials)

        let unchanged = try await sync(modules: [module], credentials: credentials)
        #expect(unchanged.downloadedFiles.isEmpty)
        #expect(!unchanged.hasChanges)

        service.filesByCourse["c1"] = [file("f2", "Blatt 1.zip", version: "2")]
        let changed = try await sync(modules: [module], credentials: credentials)
        #expect(changed.downloadedFiles == ["Blatt 1.zip"])
        #expect(try catalog.files(forModule: module.id).first?.downloadedVersion == "2")
    }

    @Test func filesRemovedInStudIPAreDeletedLocally() async throws {
        service.filesByCourse["c1"] = [file("f2", "Blatt 1.zip")]
        _ = try await sync(modules: [module], credentials: credentials)
        #expect(storage.files.count == 1)

        service.filesByCourse["c1"] = []
        _ = try await sync(modules: [module], credentials: credentials)

        #expect(try catalog.files(forModule: module.id).isEmpty)
        #expect(storage.files.isEmpty)
    }

    @Test func changingTheCourseClearsTheOldFiles() async throws {
        let modules = FakeModuleRepository()
        modules.storage = [module]
        service.filesByCourse["c1"] = [file("f2", "Blatt 1.zip")]
        _ = try await sync(modules: [module], credentials: credentials)

        let link = LinkStudIPCourseUseCase(
            repository: modules,
            removeFiles: RemoveCourseFilesUseCase(repository: catalog, storage: storage)
        )
        try link(module, courseID: "c2")

        #expect(catalog.storage.isEmpty)
        #expect(storage.files.isEmpty)
        #expect(modules.storage.first?.studIPCourseID == "c2")
    }

    @Test func storagePathKeepsTheOriginalNameSafe() {
        let moduleID = UUID()
        let path = DownloadCourseFileUseCase.storagePath(
            for: CourseFile(moduleID: moduleID, remoteID: "f9", name: "Lösung 1/2: final.py", version: "1")
        )
        #expect(path == "StudIP/\(moduleID.uuidString)/f9/Lösung 1-2- final.py")
    }
}

@MainActor
struct CourseFilesViewModelTests {
    let catalog = FakeCourseFileRepository()
    let slides = FakeSlideDocumentRepository()
    let storage = FakeFileStorage()
    let service = FakeStudIPService()
    let store = InMemoryStudIPAccountStore(credentials: credentials)
    let module = StudyModule(id: UUID(), name: "Programmierung", code: "", color: .blue, createdAt: Date(), studIPCourseID: "c1")

    private func makeViewModel() -> CourseFilesViewModel {
        CourseFilesViewModel(module: module, repository: catalog, slideRepository: slides, service: service, storage: storage, store: store)
    }

    @Test func groupsByFolderWithMainFolderFirstAndFilters() throws {
        _ = try catalog.replaceCatalog(forModule: module.id, with: [
            CourseFile(moduleID: module.id, remoteID: "a", name: "Zettel.pdf", folderPath: "Übungen", version: "1"),
            CourseFile(moduleID: module.id, remoteID: "b", name: "Info.txt", version: "1"),
            CourseFile(moduleID: module.id, remoteID: "c", name: "Aufgabe.pdf", folderPath: "Übungen", version: "1"),
        ])
        let viewModel = makeViewModel()
        viewModel.load()

        #expect(viewModel.folders.map(\.title) == ["Hauptordner", "Übungen"])
        #expect(viewModel.folders.last?.files.map(\.name) == ["Aufgabe.pdf", "Zettel.pdf"])

        viewModel.searchText = "zettel"
        #expect(viewModel.folders.map(\.title) == ["Übungen"])
    }

    @Test func openingDownloadsMissingFilesAndPrefersSlidesForPDFs() async throws {
        _ = try catalog.replaceCatalog(forModule: module.id, with: [
            CourseFile(moduleID: module.id, remoteID: "zip", name: "Code.zip", version: "1"),
            CourseFile(moduleID: module.id, remoteID: "pdf", name: "VL01.pdf", version: "1"),
        ])
        let document = SlideDocument(
            id: UUID(), moduleID: module.id, title: "VL01", fileName: "x.pdf", pageCount: 3, importedAt: Date(),
            remoteID: "pdf", remoteVersion: "1"
        )
        try slides.add(document)
        let viewModel = makeViewModel()
        viewModel.load()

        let zip = try #require(viewModel.files.first { $0.remoteID == "zip" })
        let pdf = try #require(viewModel.files.first { $0.remoteID == "pdf" })

        let zipAction = await viewModel.openAction(for: zip)
        #expect(zipAction == .file(storage.url(for: "StudIP/\(module.id.uuidString)/zip/Code.zip")))
        #expect(viewModel.downloadedCount == 1)
        #expect(await viewModel.openAction(for: pdf) == .slides(documentID: document.id))
    }

    @Test func downloadWithoutLoginShowsAnError() async throws {
        store.credentials = nil
        _ = try catalog.replaceCatalog(forModule: module.id, with: [
            CourseFile(moduleID: module.id, remoteID: "zip", name: "Code.zip", version: "1"),
        ])
        let viewModel = makeViewModel()
        viewModel.load()

        let result = await viewModel.fetch(viewModel.files[0])

        #expect(result == nil)
        #expect(viewModel.errorMessage == StudIPError.notConnected.localizedDescription)
    }
}

@MainActor
struct StudIPFolderParsingTests {
    @Test func buildsFolderPathsBelowTheCourseRoot() throws {
        let page = try StudIPJSONAPIParser.page(Data("""
        {"data": [
            {"type": "folders", "id": "root", "attributes": {"name": "Analysis I"}},
            {"type": "folders", "id": "ex", "attributes": {"name": "Übungen"}, "relationships": {"parent": {"data": {"type": "folders", "id": "root"}}}},
            {"type": "folders", "id": "s1", "attributes": {"name": "Blatt 1"}, "relationships": {"parent": {"data": {"type": "folders", "id": "ex"}}}}
        ]}
        """.utf8))
        let paths = StudIPJSONAPIParser.folderPaths(page.resources)
        #expect(paths == ["root": "", "ex": "Übungen", "s1": "Übungen/Blatt 1"])
    }

    @Test func readsParentFolderAndChangeDate() throws {
        let page = try StudIPJSONAPIParser.page(Data("""
        {"data": [{"type": "file-refs", "id": "f1",
                   "attributes": {"name": "a.zip", "chdate": "2025-10-20T08:00:00Z"},
                   "relationships": {"parent": {"data": {"type": "folders", "id": "ex"}}}}]}
        """.utf8))
        let resource = try #require(page.resources.first)
        #expect(StudIPJSONAPIParser.parentFolderID(resource) == "ex")
        #expect(StudIPJSONAPIParser.file(resource)?.changedAt == Date(timeIntervalSince1970: 1_760_947_200))
    }
}

// MARK: Browser-Anmeldung

@MainActor
struct StudIPWebLoginTests {
    let service = FakeStudIPService()
    let store = InMemoryStudIPAccountStore()
    let modules = FakeModuleRepository()
    let slides = FakeSlideDocumentRepository()
    let server = URL(string: "https://elearning.uni-oldenburg.de")!

    private func makeViewModel(now: Date = Date()) -> StudIPViewModel {
        StudIPViewModel(
            service: service,
            store: store,
            moduleRepository: modules,
            slideRepository: slides,
            importer: ImportSlideDocumentUseCase(repository: slides, storage: FakeFileStorage(), inspector: FakeInspector(pages: 3)),
            now: { now }
        )
    }

    private func cookie(_ name: String, _ value: String, domain: String, expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/"]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }

    @Test func cookieHeaderContainsOnlyCookiesForTheServer() {
        let header = StudIPSessionCookies.header(for: [
            cookie("Seminar_Session", "abc", domain: "elearning.uni-oldenburg.de"),
            cookie("tfa_trusted", "1", domain: ".uni-oldenburg.de"),
            cookie("tracking", "x", domain: "example.org"),
            cookie("old", "y", domain: "elearning.uni-oldenburg.de", expires: Date(timeIntervalSinceNow: -60)),
        ], server: server)
        #expect(header == "Seminar_Session=abc; tfa_trusted=1")
        #expect(StudIPSessionCookies.header(for: [], server: server) == nil)
    }

    @Test func loginPagesAreIgnoredUntilTheSessionIsSignedIn() async {
        let viewModel = makeViewModel()

        #expect(await viewModel.connect(server: server, cookieHeader: "Seminar_Session=gast") == false)
        #expect(!viewModel.isConnected)

        #expect(await viewModel.connect(server: server, cookieHeader: "Seminar_Session=angemeldet"))
        #expect(viewModel.account == StudIPAccount(serverURL: server, username: "tmueller13"))
        #expect(viewModel.usesBrowserLogin)
        #expect(store.credentials?.authorization == .session(cookieHeader: "Seminar_Session=angemeldet"))
    }

    @Test func expiredSessionPausesAutomaticSyncUntilNextLogin() async {
        store.credentials = StudIPCredentials(
            account: StudIPAccount(serverURL: server, username: "tmueller13"),
            authorization: .session(cookieHeader: "Seminar_Session=alt")
        )
        modules.storage = [StudyModule(id: UUID(), name: "Analysis", code: "", color: .blue, createdAt: Date(), studIPCourseID: "c1")]
        service.failure = .sessionExpired
        let viewModel = makeViewModel()

        await viewModel.syncIfDue()
        #expect(viewModel.sessionExpired)
        // Im Hintergrund keine Fehlermeldung, nur der Hinweis in den Einstellungen.
        #expect(viewModel.errorMessage == nil)

        service.failure = nil
        #expect(await viewModel.connect(server: server, cookieHeader: "Seminar_Session=angemeldet"))
        #expect(!viewModel.sessionExpired)
    }
}
