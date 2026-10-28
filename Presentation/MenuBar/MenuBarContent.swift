import AppKit
import SwiftUI

/// The menu bar item's label: an icon, plus the remaining minutes while a lecture runs.
struct MenuBarLabel: View {
    let summary: MenuBarSummary

    var body: some View {
        if summary.title.isEmpty {
            Image(systemName: "graduationcap")
        } else {
            Label(summary.title, systemImage: "record.circle")
                .labelStyle(.titleAndIcon)
        }
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
