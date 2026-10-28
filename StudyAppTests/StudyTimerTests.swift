import Foundation
import Testing
@testable import StudyApp

struct StudyTimerTests {
    let start = Date(timeIntervalSince1970: 1_760_000_000)
    let settings = StudyTimerSettings(focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, focusPhasesPerLongBreak: 2)

    @Test func runsAFocusPhaseAndReportsItWhenTimeIsUp() {
        var timer = StudyTimer(settings: settings)
        timer.start(at: start)
        #expect(timer.isRunning)
        #expect(timer.remaining(at: start.addingTimeInterval(60)) == 24 * 60)
        #expect(timer.tick(at: start.addingTimeInterval(24 * 60)) == nil)

        let completion = timer.tick(at: start.addingTimeInterval(25 * 60))
        #expect(completion == StudyTimer.Completion(phase: .focus, startedAt: start, duration: 25 * 60))
        #expect(timer.phase == .shortBreak)
        #expect(!timer.isRunning)
    }

    @Test func pauseKeepsTheRemainingTime() {
        var timer = StudyTimer(settings: settings)
        timer.start(at: start)
        timer.pause(at: start.addingTimeInterval(10 * 60))
        #expect(timer.isPaused)
        #expect(timer.remaining(at: start.addingTimeInterval(60 * 60)) == 15 * 60)

        let resumed = start.addingTimeInterval(60 * 60)
        timer.start(at: resumed)
        // The recorded start stays the original one.
        #expect(timer.tick(at: resumed.addingTimeInterval(15 * 60))?.startedAt == start)
    }

    @Test func longBreakFollowsEveryNthFocusPhase() {
        var timer = StudyTimer(settings: settings)
        var now = start
        func finishPhase() {
            timer.start(at: now)
            now = now.addingTimeInterval(timer.phaseLength)
            _ = timer.tick(at: now)
        }
        finishPhase()
        #expect(timer.phase == .shortBreak)
        finishPhase()
        #expect(timer.phase == .focus)
        finishPhase()
        #expect(timer.phase == .longBreak)
        #expect(timer.completedFocusPhases == 2)
    }

    @Test func skippingAFocusPhaseDoesNotCountIt() {
        var timer = StudyTimer(settings: settings)
        timer.skip()
        #expect(timer.phase == .shortBreak)
        #expect(timer.completedFocusPhases == 0)
        timer.skip()
        #expect(timer.phase == .focus)
    }

    @Test func storedSettingsWithoutNewKeysStayReadable() throws {
        let settings = try JSONDecoder().decode(StudyTimerSettings.self, from: Data(#"{"focusMinutes":50}"#.utf8))
        #expect(settings.focusMinutes == 50)
        #expect(settings.shortBreakMinutes == 5)
    }
}

struct StudyStatisticsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func session(_ day: Int, minutes: Double, module: UUID? = nil) -> StudySession {
        StudySession(id: UUID(), moduleID: module, startedAt: date(day), duration: minutes * 60)
    }

    @Test func sumsDaysWeekAndModules() {
        let analysis = UUID()
        let sessions = [
            session(28, minutes: 25, module: analysis),
            session(28, minutes: 25, module: analysis),
            session(27, minutes: 25),
            session(20, minutes: 25, module: analysis), // previous week
        ]
        let statistics = StudyStatistics(sessions: sessions, now: date(28, 18), calendar: calendar)

        #expect(statistics.lastSevenDays.count == 7)
        #expect(statistics.lastSevenDays.last == .init(date: date(28, 0), minutes: 50))
        #expect(statistics.minutesThisWeek == 75)
        #expect(statistics.modulesThisWeek.first == .init(moduleID: analysis, minutes: 50))
    }

    @Test func streakCountsConsecutiveDaysUpToTodayOrYesterday() {
        let sessions = [session(25, minutes: 25), session(26, minutes: 25), session(27, minutes: 25), session(23, minutes: 25)]
        #expect(StudyStatistics(sessions: sessions, now: date(28, 9), calendar: calendar).streakDays == 3)
        #expect(StudyStatistics(sessions: sessions + [session(28, minutes: 25)], now: date(28, 20), calendar: calendar).streakDays == 4)
        #expect(StudyStatistics(sessions: sessions, now: date(30, 9), calendar: calendar).streakDays == 0)
    }
}

@MainActor
final class InMemoryStudySessionRepository: StudySessionRepository {
    var sessions: [StudySession] = []
    func all() throws -> [StudySession] { sessions }
    func add(_ session: StudySession) throws { sessions.append(session) }
    func deleteSessions(forModule moduleID: UUID) throws { sessions.removeAll { $0.moduleID == moduleID } }
    func deleteAll() throws { sessions.removeAll() }
}

@MainActor
struct RecordStudySessionTests {
    @Test func ignoresPhasesShorterThanAMinute() throws {
        let repository = InMemoryStudySessionRepository()
        let record = RecordStudySessionUseCase(repository: repository)
        try record(moduleID: nil, startedAt: .now, duration: 30)
        try record(moduleID: nil, startedAt: .now, duration: 25 * 60)
        #expect(repository.sessions.count == 1)
    }
}

@MainActor
struct StudyTimerNotificationTests {
    @Test func planSyncKeepsTheTimerNotification() async throws {
        let scheduler = FakeNotificationScheduler()
        await scheduler.schedule([
            StudyNotification(id: StudyNotification.studyTimerIdentifier, title: "Pause", body: "", fireDate: .now, target: .today),
            StudyNotification(id: "studyapp.lecture.alt", title: "Alt", body: "", fireDate: .now, target: .today),
        ])
        let sync = SyncNotificationsUseCase(
            scheduler: scheduler, modules: FakeModuleRepository(), calendar: InMemoryCalendarRepository(),
            assignments: FakeAssignmentRepository()
        )

        try await sync(settings: NotificationSettings(), now: .now)

        #expect(Array(scheduler.scheduled.keys) == [StudyNotification.studyTimerIdentifier])
    }
}

@MainActor
struct StudyTimerViewModelTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_760_000_000)
    }

    let repository = InMemoryStudySessionRepository()
    let settings = InMemoryStudyPreferences()
    let scheduler = FakeNotificationScheduler()
    private let clock = Clock()

    private func makeViewModel() -> StudyTimerViewModel {
        StudyTimerViewModel(repository: repository, settings: settings, scheduler: scheduler, clock: { [clock] in clock.now })
    }

    @Test func recordsAFinishedFocusPhaseForTheChosenModule() async {
        let viewModel = makeViewModel()
        let module = UUID()
        viewModel.moduleID = module
        await viewModel.start()
        #expect(viewModel.remainingText == "25:00")

        clock.now += 25 * 60
        viewModel.tick()

        #expect(repository.sessions.map(\.moduleID) == [module])
        #expect(viewModel.timer.phase == .shortBreak)
        #expect(viewModel.statistics.minutesThisWeek == 25)
    }

    @Test func pauseCancelsTheEndNotification() async {
        let viewModel = makeViewModel()
        await viewModel.start()
        #expect(scheduler.scheduled[StudyNotification.studyTimerIdentifier] != nil)

        viewModel.pause()
        #expect(scheduler.scheduled[StudyNotification.studyTimerIdentifier] == nil)
    }

    @Test func settingsChangesArePersisted() {
        let viewModel = makeViewModel()
        viewModel.settings.focusMinutes = 50
        #expect(settings.studyTimerSettings.focusMinutes == 50)
        #expect(viewModel.remainingText == "50:00")
    }
}
