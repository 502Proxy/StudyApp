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

    /// Colour with its own variant for light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(light: light, dark: dark))
    }
}

extension NSColor {
    /// `nonisolated` because dynamic colours may call their provider off the main actor.
    nonisolated convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Dynamic colour that resolves to `light` or `dark` depending on the appearance.
    nonisolated convenience init(light: UInt32, dark: UInt32) {
        self.init(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

/// Central colours, spacing and fonts. All views use these tokens only.
///
/// The dark variants use the neutral greys of macOS so that content matches the system sidebar,
/// toolbar and title bar. Every text colour keeps at least 4.5:1 contrast on its surface.
enum Theme {
    /// Blue accent for fills, tints and selection; the same colour is the `AccentColor` asset.
    static let accent = Color(light: 0x0062CC, dark: 0x0A6CD6)
    /// Accent for text and small symbols; lighter in dark mode so it stays readable.
    static let accentText = Color(light: 0x0062CC, dark: 0x4DA3FF)
    static let accentSoft = Color(light: 0xE5F0FF, dark: 0x243F5C)
    /// Window background behind cards and lists.
    static let background = Color(nsColor: AppKitColors.background)
    /// Cards, tiles and grouped content.
    static let surface = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    /// Recessed areas inside cards (chips, input fields, code blocks).
    static let surfaceSecondary = Color(light: 0xF2F2F7, dark: 0x3A3A3C)
    /// Background of the note editor and preview.
    static let editorBackground = Color(light: 0xFFFFFF, dark: 0x232325)
    static let surfaceBorder = Color(light: 0xE5E5EA, dark: 0x38383A)
    static let textPrimary = Color(light: 0x1D1D1F, dark: 0xF5F5F7)
    static let textSecondary = Color(light: 0x6E6E73, dark: 0xAEAEB2)
    static let textTertiary = Color(light: 0x8E8E93, dark: 0x98989D)
    static let success = Color(light: 0x248A3D, dark: 0x30D158)
    static let warning = Color(light: 0xB25000, dark: 0xFFD60A)
    static let danger = Color(light: 0xD70015, dark: 0xFF6961)
    /// Marks running lectures.
    static let live = Color(light: 0xD70015, dark: 0xFF6961)
    static let shadow = Color(light: 0x1B1F3B, dark: 0x000000)

    /// Tokens for AppKit views (PDFKit) that cannot use SwiftUI colours.
    enum AppKitColors {
        static let background = NSColor(light: 0xF5F5F7, dark: 0x1C1C1E)
        /// Behind PDF pages; darker than `background` so white pages stand out.
        static let readerBackground = NSColor(light: 0xE8E8ED, dark: 0x161618)
    }

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
