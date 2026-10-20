import Foundation

extension String {
    /// Ohne führende und abschließende Leerzeichen und Zeilenumbrüche.
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `true`, wenn der Text nur aus Leerraum besteht.
    var isBlank: Bool { trimmed.isEmpty }
}
