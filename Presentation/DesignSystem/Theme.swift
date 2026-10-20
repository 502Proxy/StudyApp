import AppKit
import SwiftUI

extension Color {
    /// Erzeugt eine sRGB-Farbe aus einem Hex-Wert, z. B. `Color(hex: 0x7C5CFC)`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Farbe mit eigener Variante für hellen und dunklen Modus.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    /// `nonisolated`, weil dynamische Farben ihren Provider außerhalb des Main Actors aufrufen können.
    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// Zentrale Farben, Abstände und Schriften. Hell und luftig als Standard, mit passender
/// Dunkel-Variante. Alle Ansichten greifen ausschließlich hierauf zu.
enum Theme {
    /// Indigo als Akzent; dieselbe Farbe liegt als `AccentColor` im Asset-Katalog.
    static let accent = Color(light: 0x4F46E5, dark: 0x818CF8)
    static let accentSoft = Color(light: 0xEEF0FF, dark: 0x262842)
    /// Fensterhintergrund hinter Karten und Listen.
    static let background = Color(light: 0xF6F7FB, dark: 0x141519)
    /// Karten, Kacheln und gruppierte Inhalte.
    static let surface = Color(light: 0xFFFFFF, dark: 0x1D1E24)
    /// Zurückgenommene Flächen innerhalb von Karten (Chips, Eingabefelder, Codeblöcke).
    static let surfaceSecondary = Color(light: 0xF1F3F8, dark: 0x25262D)
    /// Hintergrund von Editor und Vorschau.
    static let editorBackground = Color(light: 0xFFFFFF, dark: 0x1A1B20)
    static let surfaceBorder = Color(light: 0xE6E8EF, dark: 0x2E3038)
    static let textPrimary = Color(light: 0x14151A, dark: 0xF2F3F5)
    static let textSecondary = Color(light: 0x6B7080, dark: 0x9A9EAD)
    static let textTertiary = Color(light: 0x9CA1B0, dark: 0x6D7180)
    static let success = Color(light: 0x16A34A, dark: 0x4ADE80)
    static let warning = Color(light: 0xD97706, dark: 0xFBBF24)
    static let danger = Color(light: 0xDC2626, dark: 0xF87171)
    /// Kennzeichnet laufende Vorlesungen.
    static let live = Color(light: 0xE11D48, dark: 0xFB7185)
    static let shadow = Color(light: 0x1B1F3B, dark: 0x000000)

    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    enum Spacing {
        static let page: CGFloat = 28
        static let section: CGFloat = 24
        static let card: CGFloat = 18
    }

    enum Typography {
        static let largeTitle = Font.system(size: 28, weight: .bold, design: .rounded)
        static let title = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let sectionTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.body
        static let caption = Font.callout
        static let small = Font.caption
        static let overline = Font.system(size: 11, weight: .semibold)
        static let metric = Font.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit()
    }
}
