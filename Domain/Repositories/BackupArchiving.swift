import Foundation

/// A backup archive unpacked into a temporary directory.
struct ExtractedBackup: Sendable {
    let manifest: BackupManifest
    let snapshot: BackupSnapshot
    /// Location of each stored file inside the extracted archive, keyed by its `FileStorage` name.
    let files: [String: URL]
    /// Temporary directory that holds the extracted archive; removed by `BackupArchiving.discard(_:)`.
    let directory: URL
}

/// Port for writing and reading backup archives. The data layer decides on the container format.
@MainActor
protocol BackupArchiving {
    /// Writes manifest, snapshot and the given files (`FileStorage` name → current location) to `destination`.
    func write(manifest: BackupManifest, snapshot: BackupSnapshot, files: [String: URL], to destination: URL) async throws
    /// Unpacks an archive. The caller must call `discard(_:)` when done.
    func read(from source: URL) async throws -> ExtractedBackup
    func discard(_ backup: ExtractedBackup)
}

/// A backup file in the automatic backup folder.
struct StoredBackup: Equatable, Sendable {
    let url: URL
    let createdAt: Date
}

/// Port for the folder that keeps automatic and safety backups.
@MainActor
protocol BackupFolder {
    var directory: URL { get }
    func backups() throws -> [StoredBackup]
    /// A new, not yet existing file URL; `label` becomes part of the file name.
    func newBackupURL(createdAt: Date, label: String) throws -> URL
    func remove(_ backup: StoredBackup) throws
}

/// All repositories that hold user data – a parameter object for operations that touch everything,
/// such as backups.
@MainActor
struct StudyDataRepositories {
    let modules: any ModuleRepository
    let slides: any SlideDocumentRepository
    let notes: any NoteRepository
    let flashcards: any FlashcardRepository
    let studySheets: any StudySheetRepository
    let assignments: any AssignmentRepository
    let calendar: any StudyCalendarRepository
    let courseFiles: any CourseFileRepository
    let exams: any ExamRepository
    let files: any FileStorage
}
