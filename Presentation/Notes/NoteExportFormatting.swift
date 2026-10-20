import Foundation

/// Dateinamen und Inhalte für den Notiz-Export. Ohne UI-Abhängigkeiten, damit es testbar bleibt.
enum NoteExportFormatting {
    static func fileExtension(for format: NoteFormat) -> String {
        switch format {
        case .plainText: "txt"
        case .markdown: "md"
        case .latex: "tex"
        }
    }

    /// Dateiname ohne Zeichen, die macOS in Dateinamen nicht erlaubt („/“, „:“).
    static func safeFileName(_ title: String, fallback: String = "Notizen") -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\\0")
        let cleaned = title.components(separatedBy: invalidCharacters).joined(separator: "-").trimmed
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// z. B. „Analysis_Seite_4.md“ oder „Vorlesung vom 19.10.2026.md“.
    static func fileName(for note: LectureNote, documentTitle: String?) -> String {
        let base: String
        if let documentTitle {
            let scope = note.pageNumber.map { "_Seite_\($0)" } ?? "_Gesamtdokument"
            base = safeFileName(documentTitle) + scope
        } else {
            base = safeFileName(note.title)
        }
        return "\(base).\(fileExtension(for: note.format))"
    }

    /// Mehrere Notizen als ein Markdown-Dokument mit Abschnitten.
    static func markdown(title: String, sections: [(heading: String, note: LectureNote)]) -> String {
        var parts = ["# \(title)"]
        for (heading, note) in sections where note.hasContent {
            parts.append("## \(heading)\n\n_Format: \(note.format.label)_\n\n\(note.content.trimmed)")
        }
        return parts.joined(separator: "\n\n---\n\n") + "\n"
    }
}
