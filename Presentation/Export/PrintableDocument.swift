import Foundation

/// Inhalt für PDF-Export und Druck: Titel, Untertitel und Abschnitte im jeweiligen Notizformat.
struct PrintableDocument: Equatable {
    struct Section: Equatable {
        var heading: String?
        var content: String
        var format: NoteFormat
    }

    var title: String
    var subtitle: String
    var sections: [Section]

    /// Vorgeschlagener Dateiname, z. B. „Analysis I – Lernzettel.pdf“.
    var fileName: String {
        NoteExportFormatting.safeFileName(title) + ".pdf"
    }
}

extension PrintableDocument {
    static func note(_ note: LectureNote, title: String, subtitle: String) -> PrintableDocument {
        PrintableDocument(
            title: title,
            subtitle: subtitle,
            sections: [Section(heading: nil, content: note.content, format: note.format)]
        )
    }

    static func notes(title: String, subtitle: String, sections: [(heading: String, note: LectureNote)]) -> PrintableDocument {
        PrintableDocument(
            title: title,
            subtitle: subtitle,
            sections: sections
                .filter { $0.note.hasContent }
                .map { Section(heading: $0.heading, content: $0.note.content, format: $0.note.format) }
        )
    }

    static func studySheet(_ sheet: StudySheet, moduleName: String) -> PrintableDocument {
        // Der Lernzettel beginnt mit „# Titel“; der steht schon im Kopf des PDFs.
        var content = sheet.content
        if let firstLine = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
           firstLine.trimmingCharacters(in: .whitespaces) == "# \(sheet.title)" {
            content = String(content.dropFirst(firstLine.count)).trimmed
        }
        return PrintableDocument(
            title: sheet.title,
            subtitle: "\(moduleName) · Lernzettel · Stand \(sheet.updatedAt.formatted(date: .long, time: .omitted))",
            sections: [Section(heading: nil, content: content, format: .markdown)]
        )
    }
}
