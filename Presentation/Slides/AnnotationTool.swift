import AppKit
import PDFKit
import SwiftUI

/// Werkzeuge im PDF-Reader.
enum AnnotationTool: String, CaseIterable, Identifiable {
    /// Text auswählen, kopieren, in Notizen übernehmen.
    case select
    case highlight
    case underline
    case strikeOut
    /// Freihand zeichnen.
    case pen
    /// Textfeld direkt auf die Folie setzen.
    case text
    /// Markierung, Zeichnung oder Textfeld per Klick entfernen.
    case eraser

    var id: Self { self }

    var title: String {
        switch self {
        case .select: "Auswählen"
        case .highlight: "Textmarker"
        case .underline: "Unterstreichen"
        case .strikeOut: "Durchstreichen"
        case .pen: "Stift"
        case .text: "Textfeld"
        case .eraser: "Radierer"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "cursorarrow"
        case .highlight: "highlighter"
        case .underline: "underline"
        case .strikeOut: "strikethrough"
        case .pen: "pencil.tip"
        case .text: "character.textbox"
        case .eraser: "eraser"
        }
    }

    /// Werkzeuge, die auf markierten Text wirken (PDF-Markup-Annotationen).
    var markupSubtype: PDFAnnotationSubtype? {
        switch self {
        case .highlight: .highlight
        case .underline: .underline
        case .strikeOut: .strikeOut
        default: nil
        }
    }

    var usesColor: Bool { self != .select && self != .eraser }

    /// Wie die PDF-Ansicht Mausereignisse behandelt.
    var interaction: AnnotatingPDFView.Interaction {
        switch self {
        case .select, .highlight, .underline, .strikeOut: .textSelection
        case .pen: .draw
        case .text: .placeText
        case .eraser: .erase
        }
    }
}

/// Farbpalette für Markierungen.
enum AnnotationColor: String, CaseIterable, Identifiable {
    case yellow
    case green
    case blue
    case pink
    case orange
    case red
    case black

    var id: Self { self }

    var label: String {
        switch self {
        case .yellow: "Gelb"
        case .green: "Grün"
        case .blue: "Blau"
        case .pink: "Rosa"
        case .orange: "Orange"
        case .red: "Rot"
        case .black: "Schwarz"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .yellow: NSColor(hex: 0xFACC15)
        case .green: NSColor(hex: 0x4ADE80)
        case .blue: NSColor(hex: 0x60A5FA)
        case .pink: NSColor(hex: 0xF472B6)
        case .orange: NSColor(hex: 0xFB923C)
        case .red: NSColor(hex: 0xEF4444)
        case .black: NSColor(hex: 0x1F2937)
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    /// Standardfarbe eines Werkzeugs: Textmarker gelb, Stift und Linien rot.
    static func defaultColor(for tool: AnnotationTool) -> AnnotationColor {
        switch tool {
        case .highlight, .text: .yellow
        default: .red
        }
    }
}

/// Strichstärken des Stifts.
enum PenWidth: Double, CaseIterable, Identifiable {
    case fine = 1.5
    case medium = 3
    case bold = 6

    var id: Self { self }

    var label: String {
        switch self {
        case .fine: "Fein"
        case .medium: "Mittel"
        case .bold: "Breit"
        }
    }
}

/// Eintrag der Markierungsliste in der Seitenleiste.
struct AnnotationSummary: Identifiable {
    let id: ObjectIdentifier
    let pageNumber: Int
    let tool: AnnotationTool
    let text: String
    let color: Color
}
