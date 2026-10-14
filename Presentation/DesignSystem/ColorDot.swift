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
                        .strokeBorder(Theme.textPrimary, lineWidth: 2)
                        .padding(-4)
                }
            }
            .accessibilityLabel(color.label)
    }
}
