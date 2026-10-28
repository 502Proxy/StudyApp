import Foundation

/// A completed focus phase of the study timer.
struct StudySession: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    /// `nil` when the timer ran without a module.
    var moduleID: UUID?
    var startedAt: Date
    var duration: TimeInterval

    var endedAt: Date { startedAt.addingTimeInterval(duration) }
}

/// Lengths of the study timer's phases (Pomodoro technique).
struct StudyTimerSettings: Codable, Equatable, Sendable {
    var focusMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    /// A long break follows every this many focus phases.
    var focusPhasesPerLongBreak = 4

    static let minuteRange = 1...120
}

extension StudyTimerSettings {
    private enum CodingKeys: String, CodingKey {
        case focusMinutes, shortBreakMinutes, longBreakMinutes, focusPhasesPerLongBreak
    }

    /// Missing keys fall back to the defaults, so stored settings survive new options.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StudyTimerSettings()
        self.init(
            focusMinutes: try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? defaults.focusMinutes,
            shortBreakMinutes: try container.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? defaults.shortBreakMinutes,
            longBreakMinutes: try container.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? defaults.longBreakMinutes,
            focusPhasesPerLongBreak: try container.decodeIfPresent(Int.self, forKey: .focusPhasesPerLongBreak)
                ?? defaults.focusPhasesPerLongBreak
        )
    }
}
