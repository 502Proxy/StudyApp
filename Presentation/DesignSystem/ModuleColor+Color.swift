import SwiftUI

extension ModuleColor {
    var color: Color {
        switch self {
        case .violet: Color(light: 0x8B5CF6, dark: 0xA78BFA)
        case .blue: Color(light: 0x3B82F6, dark: 0x60A5FA)
        case .teal: Color(light: 0x0D9488, dark: 0x2DD4BF)
        case .green: Color(light: 0x16A34A, dark: 0x4ADE80)
        case .orange: Color(light: 0xEA580C, dark: 0xFB923C)
        case .pink: Color(light: 0xDB2777, dark: 0xF472B6)
        case .red: Color(light: 0xDC2626, dark: 0xF87171)
        case .indigo: Color(light: 0x4F46E5, dark: 0x818CF8)
        case .amber: Color(light: 0xD97706, dark: 0xFBBF24)
        case .cyan: Color(light: 0x0891B2, dark: 0x22D3EE)
        }
    }

    /// Sehr helle Tönung für Flächen (Chips, Kachelhintergründe).
    var softColor: Color {
        color.opacity(0.13)
    }

    var label: String {
        switch self {
        case .violet: "Violett"
        case .blue: "Blau"
        case .teal: "Türkis"
        case .green: "Grün"
        case .orange: "Orange"
        case .pink: "Rosa"
        case .red: "Rot"
        case .indigo: "Indigo"
        case .amber: "Bernstein"
        case .cyan: "Cyan"
        }
    }
}
