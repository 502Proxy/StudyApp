import SwiftUI

extension ModuleColor {
    /// Apple's system colours, so modules look at home next to the system UI in both appearances.
    var color: Color {
        switch self {
        case .violet: Color(light: 0xAF52DE, dark: 0xBF5AF2)
        case .blue: Color(light: 0x007AFF, dark: 0x0A84FF)
        case .teal: Color(light: 0x30B0C7, dark: 0x40C8E0)
        case .green: Color(light: 0x34C759, dark: 0x30D158)
        case .orange: Color(light: 0xFF9500, dark: 0xFF9F0A)
        case .pink: Color(light: 0xFF2D55, dark: 0xFF375F)
        case .red: Color(light: 0xFF3B30, dark: 0xFF453A)
        case .indigo: Color(light: 0x5856D6, dark: 0x5E5CE6)
        case .amber: Color(light: 0xFFCC00, dark: 0xFFD60A)
        case .cyan: Color(light: 0x32ADE6, dark: 0x64D2FF)
        }
    }

    /// Light tint for areas such as chips and tile backgrounds.
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
