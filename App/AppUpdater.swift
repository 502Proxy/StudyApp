import Foundation
import Observation
#if canImport(Sparkle)
import Sparkle
#endif

/// Automatische Updates über Sparkle (kostenlos, Open Source).
///
/// Solange das Swift-Paket „Sparkle“ nicht eingebunden oder noch kein öffentlicher Schlüssel in
/// `Config/Info.plist` eingetragen ist, bleibt die Funktion deaktiviert – die App läuft trotzdem.
@MainActor
@Observable
final class AppUpdater {
    /// Updates sind technisch möglich (Paket eingebunden und konfiguriert).
    let isAvailable: Bool
    private(set) var canCheckForUpdates = false

    #if canImport(Sparkle)
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?
    #endif

    init(bundle: Bundle = .main) {
        let configured = Self.isConfigured(bundle)
        #if canImport(Sparkle)
        isAvailable = configured
        if configured {
            let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            self.controller = controller
            // Sparkle ändert `canCheckForUpdates` auf dem Main Thread.
            observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                MainActor.assumeIsolated {
                    self?.canCheckForUpdates = updater.canCheckForUpdates
                }
            }
        } else {
            controller = nil
        }
        #else
        isAvailable = false
        #endif
    }

    /// Sucht sofort nach Updates und zeigt das Ergebnis an (Menü „Nach Updates suchen …“).
    func checkForUpdates() {
        #if canImport(Sparkle)
        controller?.checkForUpdates(nil)
        #endif
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates ?? false
            #else
            false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyChecksForUpdates = newValue
            #endif
        }
    }

    /// Updates still im Hintergrund laden und beim nächsten Beenden installieren.
    var automaticallyDownloadsUpdates: Bool {
        get {
            #if canImport(Sparkle)
            controller?.updater.automaticallyDownloadsUpdates ?? false
            #else
            false
            #endif
        }
        set {
            #if canImport(Sparkle)
            controller?.updater.automaticallyDownloadsUpdates = newValue
            #endif
        }
    }

    /// „Version 1.2 (202610201530)“ für die Einstellungen.
    static func versionText(_ bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "Version \(version) (\(build))"
    }

    private static func isConfigured(_ bundle: Bundle) -> Bool {
        guard let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String else { return false }
        return !key.isEmpty && !key.hasPrefix("HIER_") && URL(string: feed) != nil
    }
}
