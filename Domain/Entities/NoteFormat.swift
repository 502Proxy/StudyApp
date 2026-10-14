import Foundation

/// The markup language a note is written in.
///
/// The raw value is persisted, so existing cases must never be renamed.
enum NoteFormat: String, CaseIterable, Codable, Sendable {
    /// Unformatted text, displayed exactly as typed.
    case plainText
    /// Markdown with headings, lists, emphasis, code, quotes and links.
    case markdown
    /// Text with LaTeX formulas (`$…$`, `$$…$$`, `\(…\)`, `\[…\]`).
    case latex
}
