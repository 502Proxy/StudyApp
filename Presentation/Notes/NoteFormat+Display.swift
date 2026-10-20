import Foundation

extension NoteFormat {
    /// Name shown in the format picker.
    var label: String {
        switch self {
        case .plainText: "Einfacher Text"
        case .markdown: "Markdown"
        case .latex: "LaTeX"
        }
    }

    /// Whether the format has a rendered preview. Plain text is always shown as typed.
    var hasPreview: Bool {
        self != .plainText
    }

    /// Placeholder shown in the empty editor.
    var placeholder: String {
        switch self {
        case .plainText: "Notizen zu diesen Folien …"
        case .markdown: "# Überschrift\n\n- Stichpunkt mit **fett** und *kursiv*"
        case .latex: "Formeln zwischen $ … $ oder $$ … $$, z. B. $e^{i\\pi} + 1 = 0$"
        }
    }
}
