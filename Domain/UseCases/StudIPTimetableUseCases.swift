import Foundation

/// Imports the dates of all linked, active modules into one calendar source „Stud.IP“, so the timetable
/// works without a calendar link.
///
/// Events are linked to their module right away and get stable IDs from the Stud.IP date ID, so a
/// refresh updates moved dates and removes deleted ones instead of duplicating them. Only dates from
/// `pastWindow` ago to `futureWindow` ahead are kept.
@MainActor
struct SyncStudIPTimetableUseCase {
    static let sourceName = "Stud.IP"
    static let pastWindow: TimeInterval = 30 * 86_400
    static let futureWindow: TimeInterval = 240 * 86_400

    let service: any StudIPScheduleService
    let repository: any StudyCalendarRepository
    var now: () -> Date = { .now }

    /// - Returns: Modules whose dates could not be loaded; the others are still imported.
    @discardableResult
    func callAsFunction(modules: [StudyModule], credentials: StudIPCredentials) async throws -> [String] {
        let linked = modules.filter { $0.studIPCourseID != nil && !$0.isArchived }
        let existing = try repository.sources().first { $0.kind == .studIP }
        guard !linked.isEmpty || existing != nil else { return [] }

        let reference = now()
        let window = reference.addingTimeInterval(-Self.pastWindow)...reference.addingTimeInterval(Self.futureWindow)
        let source = CalendarSource(
            id: existing?.id ?? UUID(),
            name: Self.sourceName,
            url: nil,
            lastSyncedAt: reference,
            kind: .studIP
        )
        var events: [StudyCalendarEvent] = []
        var failures: [String] = []
        var failedModules: Set<UUID> = []
        for module in linked {
            guard let courseID = module.studIPCourseID else { continue }
            do {
                let dates = try await service.courseDates(inCourse: courseID, credentials)
                events += dates
                    .filter { window.contains($0.start) }
                    .map { Self.event(from: $0, module: module, sourceID: source.id) }
            } catch StudIPError.sessionExpired {
                throw StudIPError.sessionExpired
            } catch {
                failures.append("\(module.name): \(error.localizedDescription)")
                failedModules.insert(module.id)
            }
        }
        // A failing module must not wipe its dates: keep the stored ones of those modules.
        if !failedModules.isEmpty {
            events += try repository.events().filter { event in
                event.sourceID == source.id && event.moduleID.map(failedModules.contains) == true
            }
        }
        try repository.save(source: source)
        try repository.replaceEvents(forSource: source.id, with: events)
        return failures
    }

    static func event(from date: StudIPCourseDate, module: StudyModule, sourceID: UUID) -> StudyCalendarEvent {
        let key = "studip:\(date.id)"
        var title = date.title.isEmpty || date.title == module.name ? module.name : "\(module.name) – \(date.title)"
        if date.isCancelled { title = "Entfällt: " + title }
        return StudyCalendarEvent(
            id: UUID.stable(from: key),
            externalID: key,
            sourceID: sourceID,
            title: title,
            details: date.details,
            location: date.location,
            startDate: date.start,
            endDate: max(date.end, date.start),
            moduleID: module.id
        )
    }
}
