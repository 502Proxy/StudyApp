import SwiftUI

/// Kleiner Farbpunkt für Modulfarben, optional als Auswahl-Schalter.
struct ColorDot: View {
    let color: ModuleColor
    var size: CGFloat = 10
    var isSelected: Bool = false

    var body: some View {
        Circle()
            .fill(color.color)
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(color.color, lineWidth: 2)
                        .padding(-4)
                }
            }
            .accessibilityLabel(color.label)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Abgerundetes Farbsymbol mit den Initialen eines Moduls, z. B. „LA“ für „Lineare Algebra II“.
struct ModuleBadge: View {
    let name: String
    let color: ModuleColor
    var size: CGFloat = 28

    var body: some View {
        Text(Self.initials(for: name))
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(color.color)
            .frame(width: size, height: size)
            .background(color.softColor, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }

    static func initials(for name: String) -> String {
        let romanNumerals: Set<String> = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]
        let fillers: Set<String> = ["für", "und", "der", "die", "das", "des", "in", "of", "and", "the", "zu", "zur"]
        let words = name.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let meaningful = words.filter { word in
            let lower = word.lowercased()
            return word.first?.isLetter == true && !romanNumerals.contains(lower) && !fillers.contains(lower)
        }
        if meaningful.count >= 2 {
            return meaningful.prefix(2).compactMap(\.first).map { String($0).uppercased() }.joined()
        }
        guard let word = meaningful.first ?? words.first else { return "?" }
        return String(word.prefix(2)).capitalized
    }
}
