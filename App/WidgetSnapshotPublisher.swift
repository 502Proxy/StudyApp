import Foundation
import WidgetKit

/// Writes the widget snapshot and reloads the widgets when it changed.
@MainActor
struct WidgetSnapshotPublisher {
    var url: URL? = WidgetSnapshotStore.defaultURL

    func publish(calendar: StudyCalendarViewModel, today: TodayViewModel, exams: ExamsViewModel) {
        let snapshot = WidgetSnapshotBuilder.snapshot(
            events: calendar.events,
            modules: today.modules,
            dueCounts: today.dueCounts,
            exams: exams.upcoming,
            now: calendar.referenceDate
        )
        // Without an App Group container (e.g. unsigned builds) there are simply no widget updates.
        guard (try? WidgetSnapshotStore.save(snapshot, to: url)) == true else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
