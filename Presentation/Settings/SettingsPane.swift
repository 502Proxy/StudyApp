import SwiftUI

/// The panes of the settings window, in toolbar order.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case schedule
    case studIP
    case notifications
    case backup
    case updates

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "Allgemein"
        case .schedule: "Stundenplan"
        case .studIP: "Stud.IP"
        case .notifications: "Mitteilungen"
        case .backup: "Backup"
        case .updates: "Updates"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .schedule: "calendar"
        case .studIP: "building.columns"
        case .notifications: "bell.badge"
        case .backup: "externaldrive"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }

    /// Height of the pane's content. The window resizes per pane like other macOS settings windows;
    /// content taller than this scrolls, so the window never outgrows a laptop display.
    var preferredHeight: CGFloat {
        switch self {
        case .general: 460
        case .schedule: 260
        case .studIP: 400
        case .notifications: 320
        case .backup: 270
        case .updates: 240
        }
    }
}

/// Shared layout of a settings pane: a grouped form with a fixed width and the pane's height.
struct SettingsForm<Content: View>: View {
    /// Wide enough that toggle labels and footers rarely wrap.
    static var width: CGFloat { 680 }

    let pane: SettingsPane
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
            .frame(width: Self.width, height: pane.preferredHeight)
    }
}
