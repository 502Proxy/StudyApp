import AppleArchive
import Foundation
import System

/// Stores backups as LZFSE-compressed Apple Archives (`.studyappbackup`):
///
/// ```text
/// manifest.json   BackupManifest
/// data.json       BackupSnapshot
/// files/…         stored files, same relative paths as in FileStorage
/// ```
///
/// File copying and compression run on a background task so large PDF libraries do not block the UI.
final class AppleArchiveBackupArchiver: BackupArchiving {
    private let fileManager = FileManager.default

    func write(manifest: BackupManifest, snapshot: BackupSnapshot, files: [String: URL], to destination: URL) async throws {
        let manifestData = try BackupJSONCoding.encode(manifest)
        let snapshotData = try BackupJSONCoding.encode(snapshot)
        let staging = try makeTemporaryDirectory()
        defer { try? fileManager.removeItem(at: staging) }

        try await Task.detached(priority: .userInitiated) {
            try Self.stage(manifest: manifestData, snapshot: snapshotData, files: files, in: staging)
            try Self.archive(directory: staging, to: destination)
        }.value
    }

    func read(from source: URL) async throws -> ExtractedBackup {
        let directory = try makeTemporaryDirectory()
        do {
            try await Task.detached(priority: .userInitiated) {
                try Self.extract(archive: source, to: directory)
            }.value
            let manifest = try BackupJSONCoding.decode(
                BackupManifest.self,
                from: Data(contentsOf: directory.appending(path: BackupJSONCoding.manifestFileName))
            )
            let snapshot = try BackupJSONCoding.decode(
                BackupSnapshot.self,
                from: Data(contentsOf: directory.appending(path: BackupJSONCoding.snapshotFileName))
            )
            return ExtractedBackup(
                manifest: manifest,
                snapshot: snapshot,
                files: existingFiles(of: snapshot, in: directory),
                directory: directory
            )
        } catch {
            try? fileManager.removeItem(at: directory)
            throw (error as? BackupError) ?? BackupError.invalidArchive
        }
    }

    func discard(_ backup: ExtractedBackup) {
        try? fileManager.removeItem(at: backup.directory)
    }

    // MARK: Staging

    private func makeTemporaryDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory.appending(path: "StudyAppBackup-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Files of the snapshot that are actually present in the extracted archive.
    private func existingFiles(of snapshot: BackupSnapshot, in directory: URL) -> [String: URL] {
        let filesDirectory = directory.appending(path: BackupJSONCoding.filesDirectoryName, directoryHint: .isDirectory)
        var result: [String: URL] = [:]
        for name in snapshot.referencedFiles where RestoreBackupUseCase.isSafeFileName(name) {
            let url = filesDirectory.appending(path: name)
            if fileManager.fileExists(atPath: url.path) { result[name] = url }
        }
        return result
    }

    /// Copies everything into a staging directory. Files that vanished since the snapshot are skipped;
    /// the restore reports them as missing.
    private nonisolated static func stage(manifest: Data, snapshot: Data, files: [String: URL], in staging: URL) throws {
        let fileManager = FileManager.default
        try manifest.write(to: staging.appending(path: BackupJSONCoding.manifestFileName))
        try snapshot.write(to: staging.appending(path: BackupJSONCoding.snapshotFileName))
        let filesDirectory = staging.appending(path: BackupJSONCoding.filesDirectoryName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        for (name, source) in files where fileManager.fileExists(atPath: source.path) {
            let target = filesDirectory.appending(path: name)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: target)
        }
    }

    // MARK: Apple Archive

    private nonisolated static func archive(directory: URL, to destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        guard let fileStream = ArchiveByteStream.fileStream(
            path: FilePath(destination.path),
            mode: .writeOnly,
            options: [.create, .truncate],
            permissions: FilePermissions(rawValue: 0o644)
        ) else { throw BackupError.invalidArchive }
        defer { try? fileStream.close() }
        guard let compressionStream = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: fileStream) else {
            throw BackupError.invalidArchive
        }
        defer { try? compressionStream.close() }
        guard let encodeStream = ArchiveStream.encodeStream(writingTo: compressionStream) else {
            throw BackupError.invalidArchive
        }
        defer { try? encodeStream.close() }
        guard let keySet = ArchiveHeader.FieldKeySet("TYP,PAT,DAT,MOD,MTM") else { throw BackupError.invalidArchive }
        try encodeStream.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keySet)
    }

    private nonisolated static func extract(archive: URL, to directory: URL) throws {
        guard let fileStream = ArchiveByteStream.fileStream(
            path: FilePath(archive.path),
            mode: .readOnly,
            options: [],
            permissions: FilePermissions(rawValue: 0o644)
        ) else { throw BackupError.invalidArchive }
        defer { try? fileStream.close() }
        guard let decompressionStream = ArchiveByteStream.decompressionStream(readingFrom: fileStream) else {
            throw BackupError.invalidArchive
        }
        defer { try? decompressionStream.close() }
        guard let decodeStream = ArchiveStream.decodeStream(readingFrom: decompressionStream) else {
            throw BackupError.invalidArchive
        }
        defer { try? decodeStream.close() }
        // Extraction goes into a fresh temporary directory; the restore only copies validated file names out of it.
        guard let extractStream = ArchiveStream.extractStream(
            extractingTo: FilePath(directory.path),
            flags: [.ignoreOperationNotPermitted]
        ) else { throw BackupError.invalidArchive }
        defer { try? extractStream.close() }
        _ = try ArchiveStream.process(readingFrom: decodeStream, writingTo: extractStream)
    }
}
