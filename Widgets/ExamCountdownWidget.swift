import SwiftUI
import WidgetKit

/// Days until the next exam with the study plan progress.
struct ExamCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ExamCountdown", provider: SnapshotProvider()) { entry in
            ExamCountdownView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Klausur-Countdown")
        .description("Tage bis zur nächsten Klausur und dein Fortschritt im Lernplan.")
        .supportedFamilies([.systemSmall])
    }
}

private struct ExamCountdownView: View {
    let entry: SnapshotEntry

    var body: some View {
        if let exam = entry.snapshot.exams.first(where: { $0.date >= Calendar.current.startOfDay(for: entry.date) }) {
            let days = Calendar.current.dateComponents(
                [.day], from: Calendar.current.startOfDay(for: entry.date), to: Calendar.current.startOfDay(for: exam.date)
            ).day ?? 0
            VStack(alignment: .leading, spacing: 4) {
                Label("Klausur", systemImage: "flag.checkered")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(exam.moduleName)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text(days == 0 ? "heute" : days == 1 ? "morgen" : "in \(days) Tagen")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(days <= 3 ? .red : .primary)
                ProgressView(value: exam.progress)
                Text("Lernplan \(Int((exam.progress * 100).rounded())) %")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(StudyAppLink.module(exam.moduleID, section: "exam").url)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(.secondary)
                Text("Keine Klausur geplant")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(StudyAppLink.today.url)
        }
    }
}
