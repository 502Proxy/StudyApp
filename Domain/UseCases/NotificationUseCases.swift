import Foundation

/// Everything the notification rules may look at.
struct NotificationPlanningInput: Sendable {
    let now: Date
    let settings: NotificationSettings
    let modules: [StudyModule]
    let events: [StudyCalendarEvent]
    let assignments: [Assignment]

    func moduleName(_ id: UUID?) -> String? {
        id.flatMap { id in modules.first { $0.id == id }?.name }
    }
}

/// One kind of reminder. New kinds are added as further rules without touching the planner (strategy pattern).
protocol NotificationRule: Sendable {
    func notifications(for input: NotificationPlanningInput) -> [StudyNotification]
}

/// Reminds of a linked lecture a few minutes before it starts.
struct LectureReminderRule: NotificationRule {
    /// Lectures further ahead are planned on a later run; this keeps the number of pending requests small.
    var horizon: TimeInterval = 7 * 86_400

    func notifications(for input: NotificationPlanningInput) -> [StudyNotification] {
        guard input.settings.lectures else { return [] }
        let lead = TimeInterval(input.settings.lectureLeadMinutes * 60)
        return input.events.compactMap { event in
            guard !event.isAllDay, let name = input.moduleName(event.moduleID), let moduleID = event.moduleID else { return nil }
            let fireDate = event.startDate.addingTimeInterval(-lead)
            guard fireDate > input.now, fireDate <= input.now.addingTimeInterval(horizon) else { return nil }
            let minutes = input.settings.lectureLeadMinutes
            let title = minutes == 0 ? "\(name) beginnt jetzt" : "\(name) beginnt in \(minutes) Min."
            let room = event.location.trimmed
            return StudyNotification(
                id: "\(StudyNotification.identifierPrefix)lecture.\(event.id.uuidString)",
                title: title,
                body: room.isEmpty ? "Folien öffnen" : "Raum \(room) · Folien öffnen",
                fireDate: fireDate,
                target: .lecture(moduleID: moduleID)
            )
        }
    }
}

/// Reminds of open assignments the day before and a few hours before they are due.
struct AssignmentReminderRule: NotificationRule {
    /// Offsets before the due date with the wording used in the title.
    static let reminders: [(offset: TimeInterval, key: String, title: String)] = [
        (24 * 3_600, "1d", "Abgabe morgen"),
        (3 * 3_600, "3h", "Abgabe in 3 Stunden"),
    ]

    func notifications(for input: NotificationPlanningInput) -> [StudyNotification] {
        guard input.settings.assignments else { return [] }
        return input.assignments.filter { !$0.isCompleted }.flatMap { assignment in
            Self.reminders.compactMap { reminder in
                let fireDate = assignment.dueDate.addingTimeInterval(-reminder.offset)
                // Assignments of archived modules stay quiet.
                guard fireDate > input.now, let module = input.moduleName(assignment.moduleID) else { return nil }
                return StudyNotification(
                    id: "\(StudyNotification.identifierPrefix)assignment.\(assignment.id.uuidString).\(reminder.key)",
                    title: "\(reminder.title): \(assignment.title)",
                    body: [module, Self.dueText(assignment.dueDate)].compactMap { $0 }.joined(separator: " · "),
                    fireDate: fireDate,
                    target: .assignment(moduleID: assignment.moduleID)
                )
            }
        }
    }

    private static func dueText(_ date: Date) -> String {
        "fällig \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// Combines the rules and keeps the result within the system's limit for pending notifications.
struct NotificationPlanner: Sendable {
    /// macOS keeps at most 64 pending requests per app; leave room for immediate ones.
    static let maximumScheduled = 60

    var rules: [any NotificationRule] = [LectureReminderRule(), AssignmentReminderRule()]

    func plan(_ input: NotificationPlanningInput) -> [StudyNotification] {
        let all = rules.flatMap { $0.notifications(for: input) }
        let soonestFirst = all.sorted { ($0.fireDate ?? input.now) < ($1.fireDate ?? input.now) }
        return Array(soonestFirst.prefix(Self.maximumScheduled))
    }

    /// Immediate notification after a background Stud.IP sync brought new material.
    static func newFiles(_ summary: StudIPSyncSummary, settings: NotificationSettings) -> StudyNotification? {
        guard settings.newFiles, summary.hasChanges else { return nil }
        let names = summary.imported + summary.updated + summary.downloadedFiles
        let title = names.count == 1 ? "Neue Datei in Stud.IP" : "\(names.count) neue Dateien in Stud.IP"
        let preview = names.prefix(3).joined(separator: ", ") + (names.count > 3 ? " …" : "")
        return StudyNotification(
            id: "\(StudyNotification.identifierPrefix)files.\(UUID().uuidString)",
            title: title,
            body: preview,
            fireDate: nil,
            target: .today
        )
    }
}

/// Port to the system's notification center.
@MainActor
protocol NotificationScheduling {
    /// The current permission, without asking the user.
    func authorization() async -> NotificationAuthorization
    /// Shows the system's permission prompt if the user has not decided yet.
    func requestAuthorization() async -> NotificationAuthorization
    /// Identifiers of all pending requests of this app.
    func pendingIdentifiers() async -> [String]
    /// Adds or replaces requests with the same identifier.
    func schedule(_ notifications: [StudyNotification]) async
    func cancel(identifiers: [String])
}

/// Brings the system's pending notifications in line with the current plan: replaces planned ones
/// and removes StudyApp requests that are no longer wanted (e.g. a cancelled lecture).
@MainActor
struct SyncNotificationsUseCase {
    let scheduler: any NotificationScheduling
    let modules: any ModuleRepository
    let calendar: any StudyCalendarRepository
    let assignments: any AssignmentRepository
    var planner = NotificationPlanner()

    /// - Returns: The notifications that are now scheduled.
    @discardableResult
    func callAsFunction(settings: NotificationSettings, now: Date) async throws -> [StudyNotification] {
        let input = NotificationPlanningInput(
            now: now,
            settings: settings,
            modules: try modules.all().filter { !$0.isArchived },
            events: try calendar.events(),
            assignments: try assignments.all()
        )
        let planned = planner.plan(input)
        let wanted = Set(planned.map(\.id))
        let stale = await scheduler.pendingIdentifiers().filter {
            $0.hasPrefix(StudyNotification.identifierPrefix) && !wanted.contains($0)
        }
        scheduler.cancel(identifiers: stale)
        await scheduler.schedule(planned)
        return planned
    }
}
