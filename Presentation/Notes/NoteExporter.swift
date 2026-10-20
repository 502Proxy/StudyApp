import SwiftUI
import UniformTypeIdentifiers

/// Eine Datei, die exportiert werden soll (Text oder PDF).
struct NoteExportFile: Identifiable {
    let id = UUID()
    let fileName: String
    let data: Data
    let contentType: UTType

    init(fileName: String, text: String) {
        self.fileName = fileName
        data = Data(text.utf8)
        contentType = Self.contentType(forExtension: (fileName as NSString).pathExtension)
    }

    init(pdfNamed fileName: String, data: Data) {
        self.fileName = fileName
        self.data = data
        contentType = .pdf
    }

    /// Exportierbare Typen; `ExportDocument` meldet genau diese als schreibbar.
    static let supportedTypes: [UTType] = [UTType.plainText, .pdf] + ["txt", "md", "tex"].compactMap {
        UTType(filenameExtension: $0, conformingTo: .plainText)
    }

    static func contentType(forExtension fileExtension: String) -> UTType {
        let type = UTType(filenameExtension: fileExtension, conformingTo: .plainText)
        return supportedTypes.first { $0 == type } ?? .plainText
    }
}

/// Inhalt für `fileExporter`. SwiftUI zeigt damit den Sichern-Dialog an und schreibt die Datei
/// mit der vom Nutzer erteilten Sandbox-Berechtigung – ohne `NSSavePanel.runModal()`.
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { NoteExportFile.supportedTypes }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
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
            document: ExportDocument(data: file?.data ?? Data()),
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

/// Erzeugt PDF bzw. Druckauftrag und meldet Fehler als Text.
@MainActor
enum PrintActions {
    static func exportPDF(_ document: PrintableDocument, into file: Binding<NoteExportFile?>, onError: @escaping (String) -> Void) {
        Task {
            do {
                let data = try await PrintRenderer.shared.pdfData(for: document)
                file.wrappedValue = NoteExportFile(pdfNamed: document.fileName, data: data)
            } catch {
                onError("Das PDF konnte nicht erstellt werden: \(error.localizedDescription)")
            }
        }
    }

    static func print(_ document: PrintableDocument, onError: @escaping (String) -> Void) {
        Task {
            do {
                try await PrintRenderer.shared.print(document)
            } catch {
                onError("Drucken ist fehlgeschlagen: \(error.localizedDescription)")
            }
        }
    }
}
