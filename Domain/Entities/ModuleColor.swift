import Foundation

/// Akzentfarbe eines Moduls. Reine Domain-Information, die konkrete
/// Darstellung (SwiftUI-Color) liegt im DesignSystem.
/// Der Rohwert wird gespeichert; bestehende Fälle dürfen nicht umbenannt werden.
enum ModuleColor: String, CaseIterable, Codable, Sendable {
    case violet
    case blue
    case teal
    case green
    case orange
    case pink
    case red
    case indigo
    case amber
    case cyan
}
