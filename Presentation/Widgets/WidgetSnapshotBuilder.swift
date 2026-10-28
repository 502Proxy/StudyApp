import Foundation

/// Turns the app's current state into the snapshot the widgets read.
enum WidgetSnapshotBuilder {
    static let lectureCount = 4
    static let examCount = 3

    static func snapshot(
        events: [StudyCalendarEvent],
        modules: [StudyModule],
        dueCounts: [UUID: Int],
        exams: [ExamOverview],
        now: Date
    ) -> WidgetSnapshot {
        let active = Dictionary(uniqueKeysWithValues: modules.filter { !$0.isArchived }.map { ($0.id, $0) })
        let lectures = events
            .filter { !$0.isAllDay && $0.moduleID.map { active[$0] != nil } == true }
            .upcoming(after: now, limit: lectureCount)
            .compactMap { event -> WidgetSnapshot.Lecture? in
                guard let moduleID = event.moduleID, let module = active[moduleID] else { return nil }
                return WidgetSnapshot.Lecture(
                    moduleID: module.id, moduleName: module.name, location: event.location, start: event.startDate, end: event.endDate
                )
            }
        let dueModules = dueCounts
            .compactMap { id, due -> WidgetSnapshot.DueModule? in
                guard due > 0, let module = active[id] else { return nil }
                return WidgetSnapshot.DueModule(moduleID: id, moduleName: module.name, count: due)
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.moduleName < $1.moduleName }
        let upcomingExams = exams.prefix(examCount).map { overview in
            WidgetSnapshot.Exam(
                moduleID: overview.module.id,
                moduleName: overview.module.name,
                title: overview.exam.title,
                date: overview.exam.startDate,
                progress: overview.plan.progress
            )
        }
        return WidgetSnapshot(lectures: lectures, dueModules: dueModules, exams: Array(upcomingExams))
    }
}
