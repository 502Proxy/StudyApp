import Foundation

/// The Pomodoro state machine: focus, short break, long break. A value type driven by explicit dates,
/// so it is deterministic and testable; the view model only feeds it the current time.
struct StudyTimer: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case focus
        case shortBreak
        case longBreak

        var isBreak: Bool { self != .focus }

        var title: String {
            switch self {
            case .focus: "Fokus"
            case .shortBreak: "Kurze Pause"
            case .longBreak: "Lange Pause"
            }
        }
    }

    /// What `tick` reports when a phase ended.
    struct Completion: Equatable, Sendable {
        let phase: Phase
        let startedAt: Date
        let duration: TimeInterval
    }

    private(set) var phase: Phase = .focus
    private(set) var completedFocusPhases = 0
    /// End of the running phase; `nil` while paused or not started.
    private(set) var phaseEnd: Date?
    /// Start of the running phase's time on the clock, for the recorded session.
    private(set) var phaseStartedAt: Date?
    private var pausedRemaining: TimeInterval?
    var settings: StudyTimerSettings

    init(settings: StudyTimerSettings = StudyTimerSettings()) {
        self.settings = settings
    }

    var isRunning: Bool { phaseEnd != nil }
    var isPaused: Bool { phaseEnd == nil && pausedRemaining != nil }

    var phaseLength: TimeInterval {
        let minutes = switch phase {
        case .focus: settings.focusMinutes
        case .shortBreak: settings.shortBreakMinutes
        case .longBreak: settings.longBreakMinutes
        }
        return TimeInterval(max(1, minutes)) * 60
    }

    func remaining(at now: Date) -> TimeInterval {
        if let phaseEnd { return max(0, phaseEnd.timeIntervalSince(now)) }
        return pausedRemaining ?? phaseLength
    }

    /// Progress of the current phase from 0 to 1.
    func progress(at now: Date) -> Double {
        1 - remaining(at: now) / phaseLength
    }

    mutating func start(at now: Date) {
        guard !isRunning else { return }
        let remaining = pausedRemaining ?? phaseLength
        if pausedRemaining == nil { phaseStartedAt = now }
        pausedRemaining = nil
        phaseEnd = now.addingTimeInterval(remaining)
    }

    mutating func pause(at now: Date) {
        guard let phaseEnd else { return }
        pausedRemaining = max(0, phaseEnd.timeIntervalSince(now))
        self.phaseEnd = nil
    }

    /// Ends the phase when its time is up and moves to the next one (not started).
    mutating func tick(at now: Date) -> Completion? {
        guard let phaseEnd, now >= phaseEnd else { return nil }
        let completion = Completion(phase: phase, startedAt: phaseStartedAt ?? now, duration: phaseLength)
        advance(countsFocus: true)
        return completion
    }

    /// Skips to the next phase. A skipped focus phase is not counted.
    mutating func skip() {
        advance(countsFocus: false)
    }

    /// Back to a fresh focus phase.
    mutating func reset() {
        self = StudyTimer(settings: settings)
    }

    private mutating func advance(countsFocus: Bool) {
        if phase == .focus {
            if countsFocus { completedFocusPhases += 1 }
            let perLongBreak = max(1, settings.focusPhasesPerLongBreak)
            let isLongBreakDue = countsFocus && completedFocusPhases.isMultiple(of: perLongBreak)
            phase = isLongBreakDue ? .longBreak : .shortBreak
        } else {
            phase = .focus
        }
        phaseEnd = nil
        phaseStartedAt = nil
        pausedRemaining = nil
    }
}
