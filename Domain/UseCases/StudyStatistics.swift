import Foundation

/// Study time figures for the statistics view, computed from recorded sessions.
struct StudyStatistics: Equatable, Sendable {
    struct Day: Equatable, Sendable {
        let date: Date
        let minutes: Int
    }

    struct ModuleTime: Equatable, Sendable {
        let moduleID: UUID?
        let minutes: Int
    }

    /// The last seven days, oldest first, including today.
    let lastSevenDays: [Day]
    /// Minutes in the current calendar week.
    let minutesThisWeek: Int
    /// Minutes per module in the current calendar week, most first.
    let modulesThisWeek: [ModuleTime]
    /// Consecutive days with at least one session, ending today (or yesterday, if today has none yet).
    let streakDays: Int

    init(sessions: [StudySession], now: Date, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        var minutesPerDay: [Date: TimeInterval] = [:]
        for session in sessions {
            minutesPerDay[calendar.startOfDay(for: session.startedAt), default: 0] += session.duration
        }
        func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }

        lastSevenDays = (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { Day(date: $0, minutes: minutes(minutesPerDay[$0] ?? 0)) }
        }

        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let thisWeek = sessions.filter { week?.contains($0.startedAt) ?? false }
        minutesThisWeek = minutes(thisWeek.reduce(0) { $0 + $1.duration })
        var perModule: [UUID?: TimeInterval] = [:]
        for session in thisWeek { perModule[session.moduleID, default: 0] += session.duration }
        modulesThisWeek = perModule
            .map { ModuleTime(moduleID: $0.key, minutes: minutes($0.value)) }
            .sorted { $0.minutes > $1.minutes }

        var streak = 0
        var day = minutesPerDay[today] == nil ? calendar.date(byAdding: .day, value: -1, to: today) : today
        while let current = day, minutesPerDay[current] != nil {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: current)
        }
        streakDays = streak
    }
}

/// Stores a completed focus phase. Phases shorter than a minute are not worth recording.
@MainActor
struct RecordStudySessionUseCase {
    static let minimumDuration: TimeInterval = 60

    let repository: any StudySessionRepository

    func callAsFunction(moduleID: UUID?, startedAt: Date, duration: TimeInterval) throws {
        guard duration >= Self.minimumDuration else { return }
        try repository.add(StudySession(id: UUID(), moduleID: moduleID, startedAt: startedAt, duration: duration))
    }
}
