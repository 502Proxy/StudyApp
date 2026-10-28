import SwiftUI
import WidgetKit

/// The widgets of StudyApp. They read the snapshot the app writes and never touch the database.
@main
struct StudyAppWidgets: WidgetBundle {
    var body: some Widget {
        NextLectureWidget()
        DueCardsWidget()
        ExamCountdownWidget()
    }
}

/// One timeline entry: the snapshot as of `date`.
struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Shared timeline: an entry now and one at every lecture start or end in the next 12 hours, so the
/// lecture widget switches from „Als Nächstes“ to „Läuft“ without the app.
struct SnapshotProvider: TimelineProvider {
    static let horizon: TimeInterval = 12 * 3_600

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let snapshot = context.isPreview ? .preview : WidgetSnapshotStore.load(from: WidgetSnapshotStore.defaultURL) ?? WidgetSnapshot()
        completion(SnapshotEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshotStore.load(from: WidgetSnapshotStore.defaultURL) ?? WidgetSnapshot()
        let dates = [now] + snapshot.changeDates(after: now).filter { $0 < now.addingTimeInterval(Self.horizon) }
        let entries = dates.map { SnapshotEntry(date: $0, snapshot: snapshot) }
        // The app reloads the timelines when its data changes; this is only the fallback.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3_600))))
    }
}

extension WidgetSnapshot {
    /// Sample data for the widget gallery.
    static var preview: WidgetSnapshot {
        let start = Date.now.addingTimeInterval(1_800)
        let module = UUID()
        return WidgetSnapshot(
            lectures: [Lecture(moduleID: module, moduleName: "Analysis I", location: "HS 1", start: start, end: start.addingTimeInterval(5_400))],
            dueModules: [DueModule(moduleID: module, moduleName: "Analysis I", count: 12), DueModule(moduleID: UUID(), moduleName: "Lineare Algebra", count: 8)],
            exams: [Exam(moduleID: module, moduleName: "Analysis I", title: "Klausur", date: .now.addingTimeInterval(12 * 86_400), progress: 0.4)]
        )
    }
}
