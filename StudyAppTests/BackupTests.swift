import Foundation
import Testing
@testable import StudyApp

// MARK: Test doubles

/// Keeps the "archive" in memory and hands out the stored files' URLs unchanged.
@MainActor
final class InMemoryBackupArchiver: BackupArchiving {
    private(set) var archives: [URL: (manifest: BackupManifest, snapshot: BackupSnapshot, files: [String: URL])] = [:]
    private(set) var discarded = 0

    func write(manifest: BackupManifest, snapshot: BackupSnapshot, files: [String: URL], to destination: URL) async throws {
        archives[destination] = (manifest, snapshot, files)
    }

    func read(from source: URL) async throws -> ExtractedBackup {
        guard let archive = archives[source] else { throw BackupError.invalidArchive }
        return ExtractedBackup(manifest: archive.manifest, snapshot: archive.snapshot, files: archive.files, directory: source)
    }

    func discard(_ backup: ExtractedBackup) {
        discarded += 1
    }

    /// Replaces the stored manifest or snapshot, e.g. to simulate an archive from a newer app version.
    func tamper(_ url: URL, manifest: BackupManifest? = nil, snapshot: BackupSnapshot? = nil, files: [String: URL]? = nil) {
        guard let archive = archives[url] else { return }
        archives[url] = (manifest ?? archive.manifest, snapshot ?? archive.snapshot, files ?? archive.files)
    }
}

@MainActor
final class InMemoryBackupFolder: BackupFolder {
    let directory = URL(fileURLWithPath: "/backups")
    var stored: [StoredBackup] = []

    func backups() throws -> [StoredBackup] { stored }

    func newBackupURL(createdAt: Date, label: String) throws -> URL {
        let url = directory.appending(path: "\(Int(createdAt.timeIntervalSince1970))-\(label).studyappbackup")
        stored.append(StoredBackup(url: url, createdAt: createdAt))
        return url
    }

    func remove(_ backup: StoredBackup) throws {
        stored.removeAll { $0 == backup }
    }
}

@MainActor
private struct DataStore {
    let modules = FakeModuleRepository()
    let slides = FakeSlideDocumentRepository()
    let notes = FakeNoteRepository()
    let flashcards = FakeFlashcardRepository()
    let studySheets = FakeStudySheetRepository()
    let assignments = FakeAssignmentRepository()
    let calendar = InMemoryCalendarRepository()
    let courseFiles = FakeCourseFileRepository()
    let exams = InMemoryExamRepository()
    let files = FakeFileStorage()

    var repositories: StudyDataRepositories {
        StudyDataRepositories(
            modules: modules, slides: slides, notes: notes, flashcards: flashcards, studySheets: studySheets,
            assignments: assignments, calendar: calendar, courseFiles: courseFiles, exams: exams, files: files
        )
    }

    /// One module with something of every kind.
    func fill(now: Date) throws -> StudyModule {
        let module = StudyModule(
            id: UUID(), name: "Analysis I", code: "MAT101", color: .blue, createdAt: now,
            credits: 9, grade: 1.7, semester: Semester(term: .winter, year: 2025), studIPCourseID: "c1"
        )
        try modules.add(module)
        let document = SlideDocument(
            id: UUID(), moduleID: module.id, title: "VL01", fileName: "doc.pdf", pageCount: 12, importedAt: now,
            remoteID: "f1", remoteVersion: "1"
        )
        try slides.add(document)
        try files.store(copyOf: URL(fileURLWithPath: "/tmp/doc.pdf"), as: document.fileName)
        try notes.add(LectureNote(
            id: UUID(), slideDocumentID: document.id, title: "Seite 3", content: "$x^2$", format: .latex,
            pageNumber: 3, createdAt: now, updatedAt: now
        ))
        try notes.add(LectureNote(
            id: UUID(), slideDocumentID: module.id, title: "Vorlesung vom 20.10.", content: "Rolle", format: .markdown,
            pageNumber: nil, createdAt: now, updatedAt: now
        ))
        try flashcards.add(Flashcard(
            id: UUID(), moduleID: module.id, sourceNoteID: nil, front: "Satz von Rolle?", back: "…", dueAt: now,
            lastReviewedAt: nil, repetitions: 2, intervalDays: 3, easeFactor: 2.5, createdAt: now, updatedAt: now
        ))
        try studySheets.add(StudySheet(
            id: UUID(), moduleID: module.id, title: "Lernzettel", content: "# Analysis", sourceNoteIDs: [], createdAt: now, updatedAt: now
        ))
        try assignments.add(Assignment(moduleID: module.id, title: "Blatt 1", dueDate: now))
        let source = CalendarSource(id: UUID(), name: "Stundenplan", url: URL(string: "https://example.com/plan.ics"), lastSyncedAt: now, kind: .subscription)
        try calendar.save(source: source)
        try calendar.replaceEvents(forSource: source.id, with: [StudyCalendarEvent(
            id: UUID(), externalID: "ana#1", sourceID: source.id, title: "Analysis I", details: "", location: "A14",
            startDate: now, endDate: now.addingTimeInterval(5_400), moduleID: module.id
        )])
        try courseFiles.replaceCatalog(forModule: module.id, with: [CourseFile(
            moduleID: module.id, remoteID: "z1", name: "Blatt1.zip", folderPath: "Übungen", version: "1",
            localFileName: "StudIP/\(module.id.uuidString)/z1/Blatt1.zip", downloadedVersion: "1"
        )])
        try files.store(copyOf: URL(fileURLWithPath: "/tmp/Blatt1.zip"), as: "StudIP/\(module.id.uuidString)/z1/Blatt1.zip")
        try exams.save(Exam(
            id: UUID(), moduleID: module.id, title: "Klausur Analysis I", startDate: now.addingTimeInterval(14 * 86_400),
            location: "Audimax", calendarEventKey: nil, completedPlanItems: ["review.final"]
        ))
        return module
    }
}

// MARK: Tests

@MainActor
struct BackupTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let destination = URL(fileURLWithPath: "/backups/manual.studyappbackup")

    @Test func snapshotContainsEverythingAndReferencesAllStoredFiles() throws {
        let store = DataStore()
        let module = try store.fill(now: now)

        let snapshot = try MakeBackupSnapshotUseCase(repositories: store.repositories)()

        #expect(snapshot.modules == [module])
        #expect(snapshot.slideDocuments.count == 1)
        #expect(snapshot.notes.count == 2)
        #expect(snapshot.flashcards.count == 1)
        #expect(snapshot.studySheets.count == 1)
        #expect(snapshot.assignments.count == 1)
        #expect(snapshot.calendarSources.count == 1)
        #expect(snapshot.calendarEvents.count == 1)
        #expect(snapshot.courseFiles.count == 1)
        #expect(snapshot.exams.map(\.title) == ["Klausur Analysis I"])
        #expect(snapshot.referencedFiles == ["StudIP/\(module.id.uuidString)/z1/Blatt1.zip", "doc.pdf"])
    }

    @Test func restoringABackupReproducesTheData() async throws {
        let original = DataStore()
        _ = try original.fill(now: now)
        let archiver = InMemoryBackupArchiver()
        let manifest = try await CreateBackupUseCase(
            repositories: original.repositories, archiver: archiver, appVersion: "1.11", now: { now }
        )(to: destination)
        #expect(manifest == BackupManifest(formatVersion: 1, appVersion: "1.11", createdAt: now, moduleCount: 1, fileCount: 2))

        let restored = DataStore()
        let summary = try await RestoreBackupUseCase(repositories: restored.repositories, archiver: archiver)(from: destination)

        let before = try MakeBackupSnapshotUseCase(repositories: original.repositories)()
        let after = try MakeBackupSnapshotUseCase(repositories: restored.repositories)()
        #expect(Self.sorted(after) == Self.sorted(before))
        #expect(restored.files.files == original.files.files)
        #expect(summary.restoredFileCount == 2)
        #expect(summary.missingFiles.isEmpty)
        #expect(archiver.discarded == 1)
    }

    @Test func restoreReplacesExistingData() async throws {
        let source = DataStore()
        _ = try source.fill(now: now)
        let archiver = InMemoryBackupArchiver()
        try await CreateBackupUseCase(repositories: source.repositories, archiver: archiver, appVersion: "1", now: { now })(to: destination)

        let target = DataStore()
        try target.modules.add(StudyModule(id: UUID(), name: "Alt", code: "", color: .teal, createdAt: now))
        try target.assignments.add(Assignment(moduleID: UUID(), title: "Verwaist", dueDate: now))

        _ = try await RestoreBackupUseCase(repositories: target.repositories, archiver: archiver)(from: destination)

        #expect(target.modules.storage.map(\.name) == ["Analysis I"])
        #expect(target.assignments.storage.map(\.title) == ["Blatt 1"])
    }

    @Test func newerFormatIsRejectedBeforeAnythingChanges() async throws {
        let source = DataStore()
        _ = try source.fill(now: now)
        let archiver = InMemoryBackupArchiver()
        try await CreateBackupUseCase(repositories: source.repositories, archiver: archiver, appVersion: "1", now: { now })(to: destination)
        archiver.tamper(destination, manifest: BackupManifest(formatVersion: 99, appVersion: "9", createdAt: now, moduleCount: 1, fileCount: 2))

        let target = DataStore()
        let existing = StudyModule(id: UUID(), name: "Bleibt", code: "", color: .teal, createdAt: now)
        try target.modules.add(existing)

        await #expect(throws: BackupError.unsupportedFormat(version: 99)) {
            try await RestoreBackupUseCase(repositories: target.repositories, archiver: archiver)(from: destination)
        }
        #expect(target.modules.storage == [existing])
        #expect(archiver.discarded == 1)
    }

    @Test(arguments: ["../outside.pdf", "/etc/passwd", "a/../../b", "a\\b", ""])
    func unsafeFileNamesAreRejected(name: String) async throws {
        let source = DataStore()
        _ = try source.fill(now: now)
        let archiver = InMemoryBackupArchiver()
        try await CreateBackupUseCase(repositories: source.repositories, archiver: archiver, appVersion: "1", now: { now })(to: destination)
        var snapshot = try MakeBackupSnapshotUseCase(repositories: source.repositories)()
        snapshot.slideDocuments[0] = SlideDocument(
            id: UUID(), moduleID: snapshot.modules[0].id, title: "Böse", fileName: name, pageCount: 1, importedAt: now
        )
        archiver.tamper(destination, snapshot: snapshot)

        await #expect(throws: BackupError.unsafePath(name)) {
            try await RestoreBackupUseCase(repositories: DataStore().repositories, archiver: archiver)(from: destination)
        }
    }

    @Test func filesMissingFromTheArchiveAreReported() async throws {
        let source = DataStore()
        _ = try source.fill(now: now)
        let archiver = InMemoryBackupArchiver()
        try await CreateBackupUseCase(repositories: source.repositories, archiver: archiver, appVersion: "1", now: { now })(to: destination)
        archiver.tamper(destination, files: ["doc.pdf": URL(fileURLWithPath: "/tmp/doc.pdf")])

        let summary = try await RestoreBackupUseCase(repositories: DataStore().repositories, archiver: archiver)(from: destination)

        #expect(summary.restoredFileCount == 1)
        #expect(summary.missingFiles.count == 1)
    }

    @Test func snapshotSurvivesJSONEncoding() throws {
        let store = DataStore()
        _ = try store.fill(now: now)
        let snapshot = try MakeBackupSnapshotUseCase(repositories: store.repositories)()

        let decoded = try BackupJSONCoding.decode(BackupSnapshot.self, from: BackupJSONCoding.encode(snapshot))

        #expect(decoded == snapshot)
        #expect(throws: BackupError.invalidArchive) {
            try BackupJSONCoding.decode(BackupSnapshot.self, from: Data("kein json".utf8))
        }
    }

    /// Arbitrary sub-second timestamps must survive; converting to seconds since 1970 loses the last bit.
    @Test func datesRoundTripExactly() throws {
        let dates = (0..<200).map { Date(timeIntervalSinceReferenceDate: 783_000_000 + Double($0) * 0.123_456_789) } + [Date()]
        let decoded = try BackupJSONCoding.decode([Date].self, from: BackupJSONCoding.encode(dates))
        #expect(decoded == dates)
    }

    @Test func semesterIsEncodedCompactly() throws {
        let json = try #require(String(bytes: BackupJSONCoding.encode([Semester(term: .winter, year: 2025)]), encoding: .utf8))
        #expect(json.contains("\"2025W\""))
    }

    private static func sorted(_ snapshot: BackupSnapshot) -> BackupSnapshot {
        var copy = snapshot
        copy.notes.sort { $0.id.uuidString < $1.id.uuidString }
        return copy
    }
}

@MainActor
struct AutomaticBackupTests {
    private let start = Date(timeIntervalSince1970: 1_760_000_000)

    @Test func policyRunsWeeklyAndKeepsTheNewest() {
        #expect(AutomaticBackupPolicy.isDue(lastBackup: nil, now: start))
        #expect(!AutomaticBackupPolicy.isDue(lastBackup: start, now: start.addingTimeInterval(6 * 86_400)))
        #expect(AutomaticBackupPolicy.isDue(lastBackup: start, now: start.addingTimeInterval(7 * 86_400)))

        let dates = (0..<5).map { start.addingTimeInterval(Double($0) * 86_400) }
        let expired = AutomaticBackupPolicy.expired(dates) { $0 }
        #expect(expired == [dates[1], dates[0]])
    }

    @Test func automaticBackupRunsOnlyWhenDueAndPrunesOldOnes() async throws {
        let store = DataStore()
        _ = try store.fill(now: start)
        let archiver = InMemoryBackupArchiver()
        let folder = InMemoryBackupFolder()
        var clock = start

        func run() async throws -> StoredBackup? {
            let create = CreateBackupUseCase(repositories: store.repositories, archiver: archiver, appVersion: "1", now: { clock })
            return try await RunAutomaticBackupUseCase(createBackup: create, folder: folder, now: { clock })()
        }

        #expect(try await run() != nil)
        clock = start.addingTimeInterval(86_400)
        #expect(try await run() == nil)

        for week in 1...4 {
            clock = start.addingTimeInterval(Double(week) * 7 * 86_400)
            #expect(try await run() != nil)
        }
        #expect(folder.stored.count == AutomaticBackupPolicy.retainedCount)
        #expect(folder.stored.map(\.createdAt).max() == clock)
    }
}

#if canImport(AppleArchive)
@MainActor
struct AppleArchiveBackupArchiverTests {
    @Test func archiveRoundTripKeepsDataAndFiles() async throws {
        let workspace = FileManager.default.temporaryDirectory.appending(path: "BackupTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let pdf = workspace.appending(path: "source.pdf")
        try Data("%PDF-1.4 test".utf8).write(to: pdf)

        var snapshot = BackupSnapshot()
        let moduleID = UUID()
        snapshot.slideDocuments = [SlideDocument(
            id: UUID(), moduleID: moduleID, title: "VL", fileName: "StudIP/a/b.pdf", pageCount: 1, importedAt: Date(timeIntervalSince1970: 0)
        )]
        let manifest = BackupManifest(formatVersion: 1, appVersion: "1", createdAt: Date(timeIntervalSince1970: 0), moduleCount: 0, fileCount: 1)
        let archive = workspace.appending(path: "test.studyappbackup")
        let archiver = AppleArchiveBackupArchiver()

        try await archiver.write(manifest: manifest, snapshot: snapshot, files: ["StudIP/a/b.pdf": pdf], to: archive)
        let extracted = try await archiver.read(from: archive)
        defer { archiver.discard(extracted) }

        #expect(extracted.manifest == manifest)
        #expect(extracted.snapshot == snapshot)
        let restoredFile = try #require(extracted.files["StudIP/a/b.pdf"])
        #expect(try Data(contentsOf: restoredFile) == Data("%PDF-1.4 test".utf8))
    }

    @Test func garbageIsAnInvalidArchive() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "garbage-\(UUID().uuidString).studyappbackup")
        try Data("not an archive".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        await #expect(throws: BackupError.invalidArchive) {
            try await AppleArchiveBackupArchiver().read(from: file)
        }
    }
}
#endif
