import Foundation
import Testing
@testable import StudyApp

// MARK: Test doubles

@MainActor
final class FakeNotificationScheduler: NotificationScheduling {
    var state: NotificationAuthorization = .authorized
    var answerToPrompt: NotificationAuthorization = .authorized
    private(set) var promptCount = 0
    private(set) var scheduled: [String: StudyNotification] = [:]
    /// Requests of other components or apps that must never be touched.
    var foreignIdentifiers: [String] = []

    func authorization() async -> NotificationAuthorization { state }

    func requestAuthorization() async -> NotificationAuthorization {
        promptCount += 1
        state = answerToPrompt
        return state
    }

    func pendingIdentifiers() async -> [String] { Array(scheduled.keys) + foreignIdentifiers }

    func schedule(_ notifications: [StudyNotification]) async {
        for notification in notifications { scheduled[notification.id] = notification }
    }

    func cancel(identifiers: [String]) {
        for identifier in identifiers {
            scheduled[identifier] = nil
            foreignIdentifiers.removeAll { $0 == identifier }
        }
    }
}

// MARK: Planner

@MainActor
struct NotificationPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    private let module = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: Date())
    private let allOn = NotificationSettings(lectures: true, lectureLeadMinutes: 10, assignments: true, newFiles: true)

    private func event(in offset: TimeInterval, linked: Bool = true, allDay: Bool = false, location: String = "A14") -> StudyCalendarEvent {
        StudyCalendarEvent(
            id: UUID(), externalID: UUID().uuidString, sourceID: UUID(), title: "Analysis I (Vorlesung)", details: "",
            location: location, startDate: now.addingTimeInterval(offset), endDate: now.addingTimeInterval(offset + 5_400),
            moduleID: linked ? module.id : nil, isAllDay: allDay
        )
    }

    private func input(
        settings: NotificationSettings? = nil,
        events: [StudyCalendarEvent] = [],
        assignments: [Assignment] = []
    ) -> NotificationPlanningInput {
        NotificationPlanningInput(now: now, settings: settings ?? allOn, modules: [module], events: events, assignments: assignments)
    }

    @Test func lectureReminderFiresBeforeTheStartAndOpensItsSlides() throws {
        let lecture = event(in: 3_600)
        let notification = try #require(LectureReminderRule().notifications(for: input(events: [lecture])).first)

        #expect(notification.fireDate == lecture.startDate.addingTimeInterval(-600))
        #expect(notification.title == "Analysis I beginnt in 10 Min.")
        #expect(notification.body == "Raum A14 · Folien öffnen")
        #expect(notification.target == .lecture(moduleID: module.id))
        #expect(notification.id.hasPrefix(StudyNotification.identifierPrefix))
    }

    @Test func lecturesWithoutModulePastOrFarAheadAreSkipped() {
        let events = [
            event(in: 3_600, linked: false),
            event(in: 300),
            event(in: 3_600, allDay: true),
            event(in: 8 * 86_400),
        ]
        #expect(LectureReminderRule().notifications(for: input(events: events)).isEmpty)
    }

    @Test func zeroLeadTimeSaysTheLectureStartsNow() throws {
        var settings = allOn
        settings.lectureLeadMinutes = 0
        let notification = try #require(LectureReminderRule().notifications(for: input(settings: settings, events: [event(in: 3_600, location: "")])).first)
        #expect(notification.title == "Analysis I beginnt jetzt")
        #expect(notification.body == "Folien öffnen")
    }

    @Test func assignmentsAreRemindedTheDayBeforeAndThreeHoursBefore() {
        let dueInTwoDays = Assignment(moduleID: module.id, title: "Blatt 3", dueDate: now.addingTimeInterval(2 * 86_400))
        let dueInFiveHours = Assignment(moduleID: module.id, title: "Blatt 4", dueDate: now.addingTimeInterval(5 * 3_600))
        var done = Assignment(moduleID: module.id, title: "Blatt 1", dueDate: now.addingTimeInterval(2 * 86_400))
        done.completedAt = now

        let notifications = AssignmentReminderRule().notifications(for: input(assignments: [dueInTwoDays, dueInFiveHours, done]))

        #expect(notifications.map(\.title).sorted() == [
            "Abgabe in 3 Stunden: Blatt 3",
            "Abgabe in 3 Stunden: Blatt 4",
            "Abgabe morgen: Blatt 3",
        ])
        #expect(notifications.allSatisfy { $0.target == .assignment(moduleID: module.id) })
    }

    @Test func disabledKindsProduceNothing() {
        let none = NotificationSettings()
        let planned = NotificationPlanner().plan(input(
            settings: none,
            events: [event(in: 3_600)],
            assignments: [Assignment(moduleID: module.id, title: "Blatt", dueDate: now.addingTimeInterval(86_400 * 2))]
        ))
        #expect(planned.isEmpty)
        #expect(NotificationPlanner.newFiles(StudIPSyncSummary(imported: ["VL01"], checkedModules: 1), settings: none) == nil)
    }

    @Test func plannerKeepsTheSoonestWithinTheSystemLimit() {
        let events = (1...80).map { event(in: Double($0) * 3_600) }
        let planned = NotificationPlanner().plan(input(events: events))
        #expect(planned.count == NotificationPlanner.maximumScheduled)
        #expect(planned.first?.fireDate == events[0].startDate.addingTimeInterval(-600))
    }

    @Test func newFilesNotificationSummarisesTheSync() throws {
        let summary = StudIPSyncSummary(imported: ["VL01", "VL02"], updated: ["VL00 (aktualisiert)"], downloadedFiles: ["Blatt1.zip"], checkedModules: 2)
        let notification = try #require(NotificationPlanner.newFiles(summary, settings: allOn))
        #expect(notification.title == "4 neue Dateien in Stud.IP")
        #expect(notification.body == "VL01, VL02, VL00 (aktualisiert) …")
        #expect(notification.fireDate == nil)
        #expect(NotificationPlanner.newFiles(StudIPSyncSummary(checkedModules: 1), settings: allOn) == nil)
    }

    @Test func settingsDefaultToOffAndSurviveEncoding() throws {
        #expect(!NotificationSettings().isAnyEnabled)
        let decoded = try JSONDecoder().decode(NotificationSettings.self, from: JSONEncoder().encode(allOn))
        #expect(decoded == allOn)
    }
}

// MARK: Sync and view model

@MainActor
struct NotificationSyncTests {
    private let now = Date(timeIntervalSince1970: 1_760_000_000)
    let scheduler = FakeNotificationScheduler()
    let modules = FakeModuleRepository()
    let calendar = InMemoryCalendarRepository()
    let assignments = FakeAssignmentRepository()
    let settings = InMemoryStudyPreferences()

    private func addLecture(archived: Bool = false) throws -> StudyCalendarEvent {
        let module = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: now, isArchived: archived)
        try modules.add(module)
        let source = UUID()
        let lecture = StudyCalendarEvent(
            id: UUID(), externalID: "a", sourceID: source, title: "Analysis I", details: "", location: "",
            startDate: now.addingTimeInterval(3_600), endDate: now.addingTimeInterval(9_000), moduleID: module.id
        )
        try calendar.replaceEvents(forSource: source, with: [lecture])
        return lecture
    }

    private var sync: SyncNotificationsUseCase {
        SyncNotificationsUseCase(scheduler: scheduler, modules: modules, calendar: calendar, assignments: assignments)
    }

    @Test func syncReplacesStudyAppRequestsAndLeavesOthersAlone() async throws {
        _ = try addLecture()
        scheduler.foreignIdentifiers = ["other.app.reminder", "\(StudyNotification.identifierPrefix)lecture.cancelled"]

        let planned = try await sync(settings: NotificationSettings(lectures: true), now: now)

        #expect(planned.count == 1)
        #expect(scheduler.scheduled.count == 1)
        #expect(scheduler.foreignIdentifiers == ["other.app.reminder"])
    }

    @Test func archivedModulesAreNotReminded() async throws {
        _ = try addLecture(archived: true)
        let planned = try await sync(settings: NotificationSettings(lectures: true), now: now)
        #expect(planned.isEmpty)
    }

    @Test func turningAKindOnAsksForPermissionOnce() async throws {
        _ = try addLecture()
        scheduler.state = .notDetermined
        let viewModel = NotificationsViewModel(
            scheduler: scheduler, modules: modules, calendar: calendar, assignments: assignments, store: settings, now: { now }
        )

        await viewModel.refresh()
        #expect(scheduler.promptCount == 0)
        #expect(scheduler.scheduled.isEmpty)

        viewModel.settings.lectures = true
        try await waitUntil { !scheduler.scheduled.isEmpty }

        #expect(scheduler.promptCount == 1)
        #expect(viewModel.authorization == .authorized)
        #expect(settings.notificationSettings.lectures)
    }

    @Test func deniedPermissionSchedulesNothing() async throws {
        _ = try addLecture()
        scheduler.state = .denied
        let viewModel = NotificationsViewModel(
            scheduler: scheduler, modules: modules, calendar: calendar, assignments: assignments, store: settings, now: { now }
        )
        viewModel.settings.lectures = true
        await viewModel.refresh()

        #expect(scheduler.promptCount == 0)
        #expect(scheduler.scheduled.isEmpty)
        #expect(viewModel.authorization == .denied)
    }

    /// Settings changes are applied in a task; wait for its effect instead of sleeping a fixed time.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
