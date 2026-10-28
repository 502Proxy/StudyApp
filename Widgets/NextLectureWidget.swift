import SwiftUI
import WidgetKit

/// The running or next lecture; a click opens its slides.
struct NextLectureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextLecture", provider: SnapshotProvider()) { entry in
            NextLectureView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Nächste Vorlesung")
        .description("Die laufende oder nächste Vorlesung mit Raum.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct NextLectureView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let lecture = entry.snapshot.lecture(at: entry.date) {
            let isLive = lecture.start <= entry.date
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isLive ? "LÄUFT" : "ALS NÄCHSTES")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isLive ? .red : .secondary)
                    Text(lecture.moduleName)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    if isLive {
                        Text("bis \(lecture.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                        ProgressView(timerInterval: lecture.start...lecture.end, countsDown: false)
                            .labelsHidden()
                            .tint(.red)
                    } else {
                        Text(lecture.start, style: .relative)
                            .font(.caption)
                    }
                    if !lecture.location.isEmpty {
                        Label(lecture.location, systemImage: "mappin")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if family == .systemMedium {
                    Divider()
                    DueCardsSummary(snapshot: entry.snapshot)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(StudyAppLink.module(lecture.moduleID, section: "slides").url)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(.secondary)
                Text("Keine Vorlesung mehr geplant")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(StudyAppLink.today.url)
        }
    }
}
