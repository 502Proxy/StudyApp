import SwiftUI
import UniformTypeIdentifiers

/// Eine Datei, die exportiert werden soll.
struct NoteExportFile: Identifiable {
    let id = UUID()
    let fileName: String
    let text: String
    let contentType: UTType

    init(fileName: String, text: String) {
        self.fileName = fileName
        self.text = text
        contentType = Self.contentType(forExtension: (fileName as NSString).pathExtension)
    }

    /// Exportierbare Typen; `TextExportDocument` meldet genau diese als schreibbar.
    static let supportedTypes: [UTType] = [UTType.plainText] + ["txt", "md", "tex"].compactMap {
        UTType(filenameExtension: $0, conformingTo: .plainText)
    }

    static func contentType(forExtension fileExtension: String) -> UTType {
        let type = UTType(filenameExtension: fileExtension, conformingTo: .plainText)
        return supportedTypes.first { $0 == type } ?? .plainText
    }
}

/// Textinhalt für `fileExporter`. SwiftUI zeigt damit den Sichern-Dialog an und schreibt die Datei
/// mit der vom Nutzer erteilten Sandbox-Berechtigung – ohne `NSSavePanel.runModal()`.
struct TextExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { NoteExportFile.supportedTypes }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct NoteExporterModifier: ViewModifier {
    @Binding var file: NoteExportFile?
    let onError: (String) -> Void

    func body(content: Content) -> some View {
        content.fileExporter(
            isPresented: Binding(
                get: { file != nil },
                set: { if !$0 { file = nil } }
            ),
            document: TextExportDocument(text: file?.text ?? ""),
            contentType: file?.contentType ?? .plainText,
            defaultFilename: file?.fileName
        ) { result in
            if case .failure(let error) = result {
                onError("Der Export ist fehlgeschlagen: \(error.localizedDescription)")
            }
            file = nil
        }
    }
}

extension View {
    /// Zeigt den Sichern-Dialog, sobald `file` gesetzt ist.
    func noteExporter(file: Binding<NoteExportFile?>, onError: @escaping (String) -> Void) -> some View {
        modifier(NoteExporterModifier(file: file, onError: onError))
    }
}
