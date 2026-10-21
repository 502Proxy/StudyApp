import SwiftUI

/// Erscheinungsbild der App. Hell ist Standard; „System“ folgt den macOS-Einstellungen.
enum AppAppearance: String, CaseIterable, Identifiable {
    case light
    case dark
    case system

    var id: Self { self }

    var title: String {
        switch self {
        case .light: "Hell"
        case .dark: "Dunkel"
        case .system: "Wie System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

/// Reine Darstellungs-Einstellungen. Sie betreffen keine Abläufe und werden deshalb direkt
/// per `@AppStorage` gelesen; fachliche Einstellungen laufen über `StudySettingsStore`.
enum ViewPreferences {
    static let appearanceKey = "settings.appearance"
    static let noteFontSizeKey = "notes.fontSize"
    static let slideReaderShowsNotesKey = "slideReader.showsNotes"
}

/// Schriftgröße für Notizen (Editor und Vorschau), einstellbar über ⌘+ / ⌘−.
enum NoteFontSize {
    nonisolated static let standard: Double = 14
    nonisolated static let range: ClosedRange<Double> = 10...28
    nonisolated static let step: Double = 1

    static func larger(_ size: Double) -> Double { min(range.upperBound, size + step) }
    static func smaller(_ size: Double) -> Double { max(range.lowerBound, size - step) }
    static func clamped(_ size: Double) -> Double { min(max(size, range.lowerBound), range.upperBound) }
}

extension EnvironmentValues {
    /// Schriftgröße für Notiz-Editor und -Vorschau; wird von den Notizansichten gesetzt.
    @Entry var noteFontSize: Double = NoteFontSize.standard
}

/// Kleine Steuerung „A− A+“ für die Notizschrift.
struct NoteFontSizeControl: View {
    @AppStorage(ViewPreferences.noteFontSizeKey) private var fontSize = NoteFontSize.standard

    var body: some View {
        HStack(spacing: 0) {
            Button {
                fontSize = NoteFontSize.smaller(fontSize)
            } label: {
                Image(systemName: "textformat.size.smaller")
                    .frame(width: 22, height: 18)
            }
            .disabled(fontSize <= NoteFontSize.range.lowerBound)
            .help("Notizschrift verkleinern (⌘−)")

            Text("\(Int(fontSize))")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 18)
                .onTapGesture(count: 2) { fontSize = NoteFontSize.standard }
                .help("Doppelklick: Standardgröße")

            Button {
                fontSize = NoteFontSize.larger(fontSize)
            } label: {
                Image(systemName: "textformat.size.larger")
                    .frame(width: 22, height: 18)
            }
            .disabled(fontSize >= NoteFontSize.range.upperBound)
            .help("Notizschrift vergrößern (⌘+)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Theme.surfaceSecondary, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Schriftgröße der Notizen")
    }
}
