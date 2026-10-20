import Foundation

/// Legt Dateien im Application-Support-Ordner der App ab.
/// Bei aktiver Sandbox liegt dieser Ordner im Container der App.
struct LocalFileStorage: FileStorage {
    let baseDirectory: URL

    init(baseDirectory: URL) throws {
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        self.baseDirectory = baseDirectory
    }

    /// Standardort: `~/Library/Application Support/StudyApp/Slides` (im Container).
    static func applicationDefault() throws -> LocalFileStorage {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = support.appending(path: "StudyApp/Slides", directoryHint: .isDirectory)
        return try LocalFileStorage(baseDirectory: directory)
    }

    func store(copyOf sourceURL: URL, as fileName: String) throws {
        // Dateien aus dem Öffnen-Dialog sind "security-scoped". Bei normalen URLs ist der Aufruf harmlos.
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }
        try FileManager.default.copyItem(at: sourceURL, to: url(for: fileName))
    }

    func url(for fileName: String) -> URL {
        baseDirectory.appending(path: fileName, directoryHint: .notDirectory)
    }

    func write(_ data: Data, as fileName: String) throws {
        // `.atomic` schreibt zuerst in eine temporäre Datei; ein Absturz hinterlässt nie ein halbes PDF.
        try data.write(to: url(for: fileName), options: .atomic)
    }

    func remove(fileName: String) throws {
        let target = url(for: fileName)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }
}
