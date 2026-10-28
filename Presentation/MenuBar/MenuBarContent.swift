import AppKit
import SwiftUI

/// Content of the menu bar popover: builds the summary inside the view, so it follows the calendar
/// and the due cards, and applies the chosen appearance.
struct MenuBarPopoverView: View {
    let calendar: StudyCalendarViewModel
    let today: TodayViewModel
    let onOpenLecture: (UUID) -> Void
    let onReviewCards: () -> Void
    let onOpenApp: () -> Void
    @AppStorage(ViewPreferences.appearanceKey) private var appearance = AppAppearance.standard

    var body: some View {
        MenuBarContent(
            summary: MenuBarSummary(calendar: calendar, dueCards: today.totalDue),
            onOpenLecture: onOpenLecture,
            onReviewCards: onReviewCards,
            onOpenApp: onOpenApp
        )
        .tint(Theme.accent)
        .preferredColorScheme(appearance.colorScheme)
    }
}

/// The window that opens from the menu bar item.
struct MenuBarContent: View {
    let summary: MenuBarSummary
    let onOpenLecture: (UUID) -> Void
    let onReviewCards: () -> Void
    let onOpenApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let lecture = summary.lecture {
                lectureSection(lecture)
            } else {
                Label("Heute keine Vorlesung mehr", systemImage: "calendar")
                    .foregroundStyle(Theme.textSecondary)
            }
            Divider()
            Button(action: onReviewCards) {
                Label(
                    summary.dueCards == 0 ? "Keine Karten fällig" : "\(summary.dueCards) Karten wiederholen",
                    systemImage: "rectangle.stack"
                )
            }
            .buttonStyle(.plain)
            .disabled(summary.dueCards == 0)
            Divider()
            HStack {
                Button("StudyApp öffnen", action: onOpenApp)
                Spacer()
                Button("Beenden") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.link)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func lectureSection(_ lecture: MenuBarSummary.Lecture) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lecture.isLive ? "Läuft gerade" : "Als Nächstes")
                .font(Theme.Typography.overline)
                .textCase(.uppercase)
                .foregroundStyle(lecture.isLive ? Theme.live : Theme.textSecondary)
            Text(lecture.moduleName)
                .font(Theme.Typography.headline)
            Text([lecture.timeText, lecture.location].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
            if lecture.isLive {
                SlimProgressBar(progress: lecture.progress, tint: Theme.live)
            }
            Button("Folien öffnen") { onOpenLecture(lecture.moduleID) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }
}
