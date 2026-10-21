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

    func verify(_ credentials: StudIPCredentials) async throws -> String {
        guard credentials.password == acceptedPassword else { throw StudIPError.unauthorized }
        return userName
    }

    func courses(_ credentials: StudIPCredentials) async throws -> [StudIPCourse] { coursesResult }

    func files(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPFile] {
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
        #expect(user.name == "Tristan Müller")
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
struct SyncStudIPSlidesTests {
    let slides = FakeSlideDocumentRepository()
    let storage = FakeFileStorage()
    let service = FakeStudIPService()

    private var sync: SyncStudIPSlidesUseCase {
        SyncStudIPSlidesUseCase(
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
        let broken = SyncStudIPSlidesUseCase(
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
        #expect(StudIPViewModel.summaryText(summary) == "Stud.IP: keine neuen Folien.")
        #expect(StudIPViewModel.summaryText(StudIPSyncSummary()) == "Noch kein Modul ist mit einer Stud.IP-Veranstaltung verknüpft.")
    }
}
