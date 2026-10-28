import Foundation
import Observation

/// Creating, restoring and scheduling backups.
@MainActor
@Observable
final class BackupViewModel {
    private(set) var isWorking = false
    private(set) var statusMessage: String?
    private(set) var lastBackup: Date?
    /// A backup the user picked for restoring; the UI asks for confirmation before `confirmRestore()`.
    var pendingRestore: URL?
    var errorMessage: String?

    var automaticBackups: Bool {
        didSet { settings.automaticBackups = automaticBackups }
    }

    var backupDirectory: URL { folder.directory }

    /// Called after a restore so every screen reloads its data.
    @ObservationIgnored var onRestored: (() -> Void)?

    private let createBackup: CreateBackupUseCase
    private let restoreBackup: RestoreBackupUseCase
    private let runAutomaticBackup: RunAutomaticBackupUseCase
    private let folder: any BackupFolder
    private let settings: any StudySettingsStore
    private let now: () -> Date
    @ObservationIgnored private var statusTask: Task<Void, Never>?

    init(
        repositories: StudyDataRepositories,
        archiver: any BackupArchiving,
        folder: any BackupFolder,
        settings: any StudySettingsStore,
        appVersion: String,
        now: @escaping () -> Date = { .now }
    ) {
        let create = CreateBackupUseCase(repositories: repositories, archiver: archiver, appVersion: appVersion, now: now)
        createBackup = create
        restoreBackup = RestoreBackupUseCase(repositories: repositories, archiver: archiver)
        runAutomaticBackup = RunAutomaticBackupUseCase(createBackup: create, folder: folder, now: now)
        self.folder = folder
        self.settings = settings
        self.now = now
        automaticBackups = settings.automaticBackups
        lastBackup = try? folder.backups().map(\.createdAt).max()
    }

    /// Suggested name for a manual backup.
    var suggestedFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "StudyApp-Backup \(formatter.string(from: now()))"
    }

    func create(at destination: URL) async {
        await perform {
            let manifest = try await self.createBackup(to: destination)
            self.lastBackup = manifest.createdAt
            self.announce(Self.createdMessage(manifest))
        }
    }

    /// Restores `pendingRestore` once the user confirmed it.
    func confirmRestore() async {
        guard let source = pendingRestore else { return }
        pendingRestore = nil
        await restore(from: source)
    }

    /// Replaces all data with the backup at `source` after saving the current data as a safety backup.
    func restore(from source: URL) async {
        await perform {
            let safety = try self.folder.newBackupURL(createdAt: self.now(), label: "Vor Wiederherstellung")
            try await self.createBackup(to: safety)
            let summary = try await self.restoreBackup(from: source)
            self.onRestored?()
            self.announce(Self.restoredMessage(summary))
        }
    }

    /// Runs on launch; stays silent unless something goes wrong.
    func runAutomaticBackupIfDue() async {
        guard settings.automaticBackups, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            if let backup = try await runAutomaticBackup() {
                lastBackup = backup.createdAt
            }
        } catch {
            errorMessage = "Das automatische Backup ist fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: Messages

    static func createdMessage(_ manifest: BackupManifest) -> String {
        let modules = manifest.moduleCount == 1 ? "1 Modul" : "\(manifest.moduleCount) Module"
        let files = manifest.fileCount == 1 ? "1 Datei" : "\(manifest.fileCount) Dateien"
        return "Backup gespeichert: \(modules), \(files)."
    }

    static func restoredMessage(_ summary: BackupRestoreSummary) -> String {
        let modules = summary.moduleCount == 1 ? "1 Modul" : "\(summary.moduleCount) Module"
        var text = "Backup vom \(summary.manifest.createdAt.formatted(date: .abbreviated, time: .shortened)) wiederhergestellt: \(modules)."
        if !summary.missingFiles.isEmpty {
            text += " \(summary.missingFiles.count) Datei(en) fehlten im Backup."
        }
        return text
    }

    // MARK: Helpers

    private func perform(_ operation: () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func announce(_ message: String) {
        statusMessage = message
        statusTask?.cancel()
        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }
}
