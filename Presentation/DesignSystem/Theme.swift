import AppKit
import SwiftUI

extension Color {
    /// Erzeugt eine sRGB-Farbe aus einem Hex-Wert, z. B. `Color(hex: 0x7C5CFC)`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Central colors and fonts. Everything maps to system colors and text styles,
/// so the app follows light/dark mode and the accent color chosen in System Settings.
enum Theme {
    /// The user's system accent color (blue by default).
    static let accent = Color.accentColor
    /// Window background behind content.
    static let background = Color(nsColor: .windowBackgroundColor)
    /// Background of grouped content such as cards and code blocks.
    static let surface = Color(nsColor: .controlBackgroundColor)
    /// Background of text editing and preview areas.
    static let editorBackground = Color(nsColor: .textBackgroundColor)
    static let surfaceBorder = Color(nsColor: .separatorColor)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary

    enum Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title2.weight(.semibold)
        static let body = Font.body
        static let caption = Font.callout
    }
}
