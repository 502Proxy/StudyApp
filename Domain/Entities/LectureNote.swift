import Foundation

/// A note the user took while studying a `SlideDocument`.
///
/// The link to the slides is a plain ID (like `SlideDocument.moduleID`); cleaning up
/// notes when their slides are deleted is the job of the delete use cases.
///
/// Free module notes (e.g. a note per lecture, written without any PDF) use the module's ID
/// as `slideDocumentID`. This keeps the storage schema unchanged; `isModuleNote(of:)` tells them apart.
struct LectureNote: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// ID of the slide document, or the module's ID for a free module note.
    let slideDocumentID: UUID
    var title: String
    var content: String
    var format: NoteFormat
    /// 1-based page the note refers to. `nil` means the note covers the whole document.
    var pageNumber: Int?
    let createdAt: Date
    var updatedAt: Date
}

extension LectureNote {
    /// Whether this is a free note of the module rather than a note attached to slides.
    func isModuleNote(of moduleID: UUID) -> Bool {
        slideDocumentID == moduleID
    }

    var hasContent: Bool { !content.isBlank }

    /// Erste aussagekräftige Zeile ohne Markdown-Zeichen, z. B. für Listen und Suchergebnisse.
    /// Eine Zeile, die nur den Titel wiederholt, wird übersprungen.
    func previewLine() -> String? {
        content
            .split(whereSeparator: \.isNewline)
            .map { Self.strippingBlockMarkers(String($0)) }
            .first { !$0.isEmpty && $0 != title }
    }

    /// Entfernt nur Zeichen am Zeilenanfang, die Blöcke markieren (Überschrift, Zitat, Aufzählung),
    /// damit Hervorhebungen wie `**fett**` im Text erhalten bleiben.
    private static func strippingBlockMarkers(_ line: String) -> String {
        var text = line.trimmed
        while let first = text.first, first == "#" || first == ">" {
            text = String(text.dropFirst()).trimmed
        }
        for bullet in ["- ", "* ", "+ ", "```"] where text.hasPrefix(bullet) {
            text = String(text.dropFirst(bullet.count)).trimmed
        }
        if let dot = text.firstIndex(of: "."), text[..<dot].allSatisfy(\.isNumber), !text[..<dot].isEmpty,
           text[text.index(after: dot)...].hasPrefix(" ") {
            text = String(text[text.index(after: dot)...]).trimmed
        }
        return text
    }
}
