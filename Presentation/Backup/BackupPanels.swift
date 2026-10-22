import AppKit
import UniformTypeIdentifiers

extension UTType {
    /// `.studyappbackup` archives, declared in `Config/Info.plist`.
    static let studyAppBackup = UTType(exportedAs: "germany.oldenburg.mueller.tristan.studyapp.backup")
}

/// Save and open panels for backups. Uses the non-blocking `begin` API instead of `runModal`,
/// which can deadlock when called from a SwiftUI menu action.
@MainActor
enum BackupPanels {
    static func chooseDestination(suggestedName: String, completion: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Backup erstellen"
        panel.prompt = "Sichern"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.studyAppBackup]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    static func chooseBackup(in directory: URL? = nil, completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Backup wiederherstellen"
        panel.prompt = "Auswählen"
        panel.allowedContentTypes = [.studyAppBackup]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = directory
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}
