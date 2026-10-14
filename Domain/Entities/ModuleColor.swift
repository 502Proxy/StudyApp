import Foundation

/// Akzentfarbe eines Moduls. Reine Domain-Information, die konkrete
/// Darstellung (SwiftUI-Color) liegt im DesignSystem.
enum ModuleColor: String, CaseIterable, Codable, Sendable {
    case violet
    case blue
    case teal
    case green
    case orange
    case pink
    case red
}
