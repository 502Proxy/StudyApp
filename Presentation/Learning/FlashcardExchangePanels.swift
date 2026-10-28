import AppKit
import UniformTypeIdentifiers

/// Open and save panels for Anki files.
enum FlashcardExchangePanels {
    static var importTypes: [UTType] {
        [.plainText, .tabSeparatedText, .commaSeparatedText] + [UTType(filenameExtension: "apkg")].compactMap { $0 }
    }

    static func chooseImport(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Karteikarten aus Anki importieren"
        panel.message = "Anki-Paket (.apkg) oder Anki-Textexport („Notizen als Klartext“)"
        panel.prompt = "Importieren"
        panel.allowedContentTypes = importTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    static func chooseExport(suggestedName: String, completion: @escaping (URL) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Karteikarten für Anki exportieren"
        panel.message = "In Anki über „Datei → Importieren“ öffnen."
        panel.prompt = "Exportieren"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }
}
