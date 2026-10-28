import Foundation

/// Everything StudyApp stores in its database, in a form that can be written to a backup archive.
///
/// The snapshot is encoded with the entities' `Codable` conformance. Adding an optional property to an
/// entity keeps older backups readable; removing or renaming one requires a new
/// `BackupManifest.currentFormatVersion` and a migration in the reader.
struct BackupSnapshot: Codable, Equatable, Sendable {
    var modules: [StudyModule] = []
    var slideDocuments: [SlideDocument] = []
    var notes: [LectureNote] = []
    var flashcards: [Flashcard] = []
    var studySheets: [StudySheet] = []
    var assignments: [Assignment] = []
    var calendarSources: [CalendarSource] = []
    var calendarEvents: [StudyCalendarEvent] = []
    var courseFiles: [CourseFile] = []
    /// Manual exams plus the stored state (hidden, study plan progress) of detected ones.
    var exams: [Exam] = []

    /// Names of the stored files (`FileStorage`) the snapshot refers to: slide PDFs and downloaded course files.
    var referencedFiles: [String] {
        let names = slideDocuments.map(\.fileName) + courseFiles.compactMap(\.localFileName)
        return Array(Set(names)).sorted()
    }
}

/// Describes a backup archive; read first so incompatible archives are rejected before anything changes.
struct BackupManifest: Codable, Equatable, Sendable {
    /// Version of the archive layout and snapshot encoding. Increase it for incompatible changes.
    static let currentFormatVersion = 1

    let formatVersion: Int
    let appVersion: String
    let createdAt: Date
    let moduleCount: Int
    let fileCount: Int
}

enum BackupError: LocalizedError, Equatable {
    case unsupportedFormat(version: Int)
    case invalidArchive
    case unsafePath(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let version):
            "Das Backup stammt aus einer neueren StudyApp-Version (Format \(version)). Bitte aktualisiere die App zuerst."
        case .invalidArchive:
            "Die Datei ist kein gültiges StudyApp-Backup."
        case .unsafePath(let name):
            "Das Backup enthält einen ungültigen Dateipfad („\(name)“)."
        }
    }
}

/// When automatic backups run and which old ones are removed.
enum AutomaticBackupPolicy {
    static let interval: TimeInterval = 7 * 86_400
    /// Every backup contains all PDFs, so only a few are kept to limit disk usage.
    static let retainedCount = 3

    static func isDue(lastBackup: Date?, now: Date) -> Bool {
        guard let lastBackup else { return true }
        return now.timeIntervalSince(lastBackup) >= interval
    }

    /// The backups to delete so that only the newest `retainedCount` remain.
    static func expired<Item>(_ backups: [Item], date: (Item) -> Date) -> [Item] {
        Array(backups.sorted { date($0) > date($1) }.dropFirst(retainedCount))
    }
}
