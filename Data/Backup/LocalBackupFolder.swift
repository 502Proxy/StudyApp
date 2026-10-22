import Foundation

/// Keeps automatic and safety backups in `Application Support/StudyApp/Backups` inside the app container.
struct LocalBackupFolder: BackupFolder {
    static let fileExtension = "studyappbackup"

    let directory: URL

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
    }

    static func applicationDefault() throws -> LocalBackupFolder {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try LocalBackupFolder(directory: support.appending(path: "StudyApp/Backups", directoryHint: .isDirectory))
    }

    func backups() throws -> [StoredBackup] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == Self.fileExtension }
            .map { url in
                let created = try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
                return StoredBackup(url: url, createdAt: created)
            }
    }

    func newBackupURL(createdAt: Date, label: String) throws -> URL {
        var url = directory.appending(path: Self.fileName(createdAt: createdAt, label: label))
        var counter = 2
        // Two backups in the same minute must not overwrite each other.
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appending(path: Self.fileName(createdAt: createdAt, label: "\(label) \(counter)"))
            counter += 1
        }
        return url
    }

    func remove(_ backup: StoredBackup) throws {
        try FileManager.default.removeItem(at: backup.url)
    }

    /// „StudyApp-Backup 2026-10-22 14.05 (Automatisch).studyappbackup“ – sortable and readable in Finder.
    static func fileName(createdAt: Date, label: String? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        let suffix = label.map { " (\($0))" } ?? ""
        return "StudyApp-Backup \(formatter.string(from: createdAt))\(suffix).\(fileExtension)"
    }
}
