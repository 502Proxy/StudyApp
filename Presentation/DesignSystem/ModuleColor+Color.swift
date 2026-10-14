import SwiftUI

extension ModuleColor {
    var color: Color {
        switch self {
        case .violet: Color.purple
        case .blue: Color.blue
        case .teal: Color.teal
        case .green: Color.green
        case .orange: Color.orange
        case .pink: Color.pink
        case .red: Color.red
        }
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
        }
    }
}
