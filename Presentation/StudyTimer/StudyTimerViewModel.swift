import Foundation
import Observation

/// The app-wide study timer: one timer, shown in the toolbar (and the menu bar), plus the statistics.
@MainActor
@Observable
final class StudyTimerViewModel {
    private(set) var timer: StudyTimer
    /// Module the focus time is counted for; `nil` counts it without a module.
    var moduleID: UUID?
    private(set) var sessions: [StudySession] = []
    /// Updated every second while the timer runs, so the remaining time redraws.
    private(set) var now: Date
    var errorMessage: String?

    private let repository: any StudySessionRepository
    private let record: RecordStudySessionUseCase
    private let settingsStore: any StudySettingsStore
    private let scheduler: (any NotificationScheduling)?
    private let clock: () -> Date
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    init(
        repository: any StudySessionRepository,
        settings: any StudySettingsStore,
        scheduler: (any NotificationScheduling)? = nil,
        clock: @escaping () -> Date = { .now }
    ) {
        self.repository = repository
        record = RecordStudySessionUseCase(repository: repository)
        settingsStore = settings
        self.scheduler = scheduler
        self.clock = clock
        timer = StudyTimer(settings: settings.studyTimerSettings)
        now = clock()
    }

    var settings: StudyTimerSettings {
        get { timer.settings }
        set {
            timer.settings = newValue
            settingsStore.studyTimerSettings = newValue
        }
    }

    var remaining: TimeInterval { timer.remaining(at: now) }
    var progress: Double { timer.progress(at: now) }
    var isActive: Bool { timer.isRunning || timer.isPaused }

    /// „24:59“.
    var remainingText: String { Self.clockText(remaining) }

    var statistics: StudyStatistics { StudyStatistics(sessions: sessions, now: now) }

    func load() {
        do {
            sessions = try repository.all()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func start() async {
        now = clock()
        timer.start(at: now)
        startTicking()
        await scheduleEndNotification()
    }

    func pause() {
        now = clock()
        timer.pause(at: now)
        cancelEndNotification()
    }

    func skip() {
        timer.skip()
        cancelEndNotification()
    }

    func reset() {
        timer.reset()
        cancelEndNotification()
    }

    /// Advances the timer; records a finished focus phase.
    func tick() {
        now = clock()
        guard let completion = timer.tick(at: now) else { return }
        if completion.phase == .focus {
            do {
                try record(moduleID: moduleID, startedAt: completion.startedAt, duration: completion.duration)
                load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// „45 Min.“ or „2 Std. 5 Min.“.
    static func durationText(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) Min." }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60) Std." : "\(minutes / 60) Std. \(rest) Min."
    }

    static func clockText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded(.up))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Private

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while let self, self.timer.isRunning, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.tick()
            }
        }
    }

    private func scheduleEndNotification() async {
        guard let scheduler, let end = timer.phaseEnd else { return }
        let isFocus = timer.phase == .focus
        let notification = StudyNotification(
            id: StudyNotification.studyTimerIdentifier,
            title: isFocus ? "Fokuszeit vorbei" : "Pause vorbei",
            body: isFocus ? "Zeit für eine Pause." : "Weiter geht's mit der nächsten Fokusphase.",
            fireDate: end,
            target: .today
        )
        guard await scheduler.authorization() == .authorized else { return }
        await scheduler.schedule([notification])
    }

    private func cancelEndNotification() {
        scheduler?.cancel(identifiers: [StudyNotification.studyTimerIdentifier])
    }
}
