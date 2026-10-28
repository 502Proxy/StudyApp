import Foundation

/// Reads every piece of user data into a `BackupSnapshot`.
@MainActor
struct MakeBackupSnapshotUseCase {
    let repositories: StudyDataRepositories

    func callAsFunction() throws -> BackupSnapshot {
        var snapshot = BackupSnapshot()
        snapshot.modules = try repositories.modules.all()
        for module in snapshot.modules {
            let documents = try repositories.slides.documents(forModule: module.id)
            snapshot.slideDocuments += documents
            // Free lecture notes are stored under the module's ID, slide notes under their document's ID.
            for ownerID in [module.id] + documents.map(\.id) {
                snapshot.notes += try repositories.notes.notes(forSlideDocument: ownerID)
            }
            snapshot.flashcards += try repositories.flashcards.cards(forModule: module.id)
            snapshot.studySheets += try repositories.studySheets.sheets(forModule: module.id)
            snapshot.courseFiles += try repositories.courseFiles.files(forModule: module.id)
        }
        snapshot.assignments = try repositories.assignments.all()
        snapshot.calendarSources = try repositories.calendar.sources()
        snapshot.calendarEvents = try repositories.calendar.events()
        snapshot.exams = try repositories.exams.all()
        snapshot.studySessions = try repositories.studySessions.all()
        return snapshot
    }
}

/// Writes all user data and stored files into a backup archive.
@MainActor
struct CreateBackupUseCase {
    let repositories: StudyDataRepositories
    let archiver: any BackupArchiving
    let appVersion: String
    var now: () -> Date = { Date() }

    @discardableResult
    func callAsFunction(to destination: URL) async throws -> BackupManifest {
        let snapshot = try MakeBackupSnapshotUseCase(repositories: repositories)()
        let files = Dictionary(uniqueKeysWithValues: snapshot.referencedFiles.map { ($0, repositories.files.url(for: $0)) })
        let manifest = BackupManifest(
            formatVersion: BackupManifest.currentFormatVersion,
            appVersion: appVersion,
            createdAt: now(),
            moduleCount: snapshot.modules.count,
            fileCount: files.count
        )
        try await archiver.write(manifest: manifest, snapshot: snapshot, files: files, to: destination)
        return manifest
    }
}

struct BackupRestoreSummary: Equatable, Sendable {
    let manifest: BackupManifest
    let moduleCount: Int
    let restoredFileCount: Int
    /// Files the snapshot refers to but the archive does not contain (e.g. deleted before the backup).
    let missingFiles: [String]
}

/// Replaces all user data with the content of a backup archive.
///
/// The archive is read and validated completely before anything is deleted. Callers should create a
/// safety backup first, because a failure while inserting cannot be rolled back.
@MainActor
struct RestoreBackupUseCase {
    let repositories: StudyDataRepositories
    let archiver: any BackupArchiving

    func callAsFunction(from source: URL) async throws -> BackupRestoreSummary {
        let backup = try await archiver.read(from: source)
        defer { archiver.discard(backup) }
        try Self.validate(backup)

        try removeAllData()
        try insert(backup.snapshot)

        var restored = 0
        var missing: [String] = []
        for name in backup.snapshot.referencedFiles {
            guard let url = backup.files[name] else {
                missing.append(name)
                continue
            }
            try? repositories.files.remove(fileName: name)
            try repositories.files.store(copyOf: url, as: name)
            restored += 1
        }
        return BackupRestoreSummary(
            manifest: backup.manifest,
            moduleCount: backup.snapshot.modules.count,
            restoredFileCount: restored,
            missingFiles: missing
        )
    }

    /// Rejects archives from newer app versions and file names that would escape the storage directory.
    static func validate(_ backup: ExtractedBackup) throws {
        guard backup.manifest.formatVersion <= BackupManifest.currentFormatVersion else {
            throw BackupError.unsupportedFormat(version: backup.manifest.formatVersion)
        }
        if let unsafe = backup.snapshot.referencedFiles.first(where: { !isSafeFileName($0) }) {
            throw BackupError.unsafePath(unsafe)
        }
    }

    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty
            && !name.hasPrefix("/")
            && !name.contains("\\")
            && !name.split(separator: "/").contains("..")
    }

    private func removeAllData() throws {
        let deleteModule = DeleteModuleUseCase(
            repository: repositories.modules,
            slideRepository: repositories.slides,
            noteRepository: repositories.notes,
            flashcardRepository: repositories.flashcards,
            studySheetRepository: repositories.studySheets,
            fileStorage: repositories.files,
            calendarRepository: repositories.calendar,
            assignmentRepository: repositories.assignments,
            courseFileRepository: repositories.courseFiles,
            examRepository: repositories.exams
        )
        for module in try repositories.modules.all() {
            try deleteModule(module)
        }
        // Assignments of modules that no longer exist would otherwise survive.
        for assignment in try repositories.assignments.all() {
            try repositories.assignments.delete(id: assignment.id)
        }
        for source in try repositories.calendar.sources() {
            try repositories.calendar.deleteSource(id: source.id)
        }
        for exam in try repositories.exams.all() {
            try repositories.exams.delete(id: exam.id)
        }
        try repositories.studySessions.deleteAll()
    }

    private func insert(_ snapshot: BackupSnapshot) throws {
        for module in snapshot.modules { try repositories.modules.add(module) }
        for document in snapshot.slideDocuments { try repositories.slides.add(document) }
        for note in snapshot.notes { try repositories.notes.add(note) }
        for card in snapshot.flashcards { try repositories.flashcards.add(card) }
        for sheet in snapshot.studySheets { try repositories.studySheets.add(sheet) }
        for assignment in snapshot.assignments { try repositories.assignments.add(assignment) }
        for source in snapshot.calendarSources {
            try repositories.calendar.save(source: source)
            try repositories.calendar.replaceEvents(
                forSource: source.id,
                with: snapshot.calendarEvents.filter { $0.sourceID == source.id }
            )
        }
        for exam in snapshot.exams { try repositories.exams.save(exam) }
        for session in snapshot.studySessions { try repositories.studySessions.add(session) }
        for (moduleID, files) in Dictionary(grouping: snapshot.courseFiles, by: \.moduleID) {
            try repositories.courseFiles.replaceCatalog(forModule: moduleID, with: files)
        }
    }
}

/// Creates a backup in the backup folder when the last one is older than `AutomaticBackupPolicy.interval`
/// and removes backups beyond `AutomaticBackupPolicy.retainedCount`.
@MainActor
struct RunAutomaticBackupUseCase {
    let createBackup: CreateBackupUseCase
    let folder: any BackupFolder
    var now: () -> Date = { Date() }

    /// - Returns: The new backup, or `nil` when none was due.
    @discardableResult
    func callAsFunction() async throws -> StoredBackup? {
        let timestamp = now()
        let lastBackup = try folder.backups().map(\.createdAt).max()
        guard AutomaticBackupPolicy.isDue(lastBackup: lastBackup, now: timestamp) else { return nil }

        let url = try folder.newBackupURL(createdAt: timestamp, label: "Automatisch")
        try await createBackup(to: url)
        for expired in AutomaticBackupPolicy.expired(try folder.backups(), date: \.createdAt) {
            try folder.remove(expired)
        }
        return StoredBackup(url: url, createdAt: timestamp)
    }
}
