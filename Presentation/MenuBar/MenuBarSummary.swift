import Foundation

/// What the menu bar item shows: the running lecture with remaining time, otherwise the next one,
/// the due flashcards and the study timer. Pure, so it is easy to test.
struct MenuBarSummary: Equatable {
    /// The study timer while it runs or is paused.
    struct StudyTimerStatus: Equatable {
        /// „Fokus“, „Kurze Pause“ …
        let phaseTitle: String
        /// „24:59“.
        let remainingText: String
        let isRunning: Bool
    }

    struct Lecture: Equatable {
        let moduleID: UUID
        let moduleName: String
        let location: String
        let isLive: Bool
        /// „noch 38 Min.“ or „um 14:15“.
        let timeText: String
        let progress: Double
    }

    let lecture: Lecture?
    let dueCards: Int
    let studyTimer: StudyTimerStatus?

    /// Short text next to the menu bar icon: the running timer first, then a running lecture; empty otherwise.
    var title: String {
        if let studyTimer, studyTimer.isRunning { return studyTimer.remainingText }
        guard let lecture, lecture.isLive else { return "" }
        return lecture.timeText.replacingOccurrences(of: "noch ", with: "")
    }

    /// SF Symbol of the menu bar item, matching `title`.
    var symbolName: String {
        if let studyTimer, studyTimer.isRunning { return "timer" }
        return lecture?.isLive == true ? "record.circle" : "graduationcap"
    }

    init(lecture: Lecture?, dueCards: Int, studyTimer: StudyTimerStatus? = nil) {
        self.lecture = lecture
        self.dueCards = dueCards
        self.studyTimer = studyTimer
    }

    @MainActor
    init(calendar: StudyCalendarViewModel, dueCards: Int, studyTimer: StudyTimerViewModel? = nil) {
        self.studyTimer = studyTimer.flatMap { Self.status(of: $0) }
        let now = calendar.referenceDate
        let event = calendar.currentLecture ?? calendar.nextLecture
        if let event, let module = calendar.module(for: event) {
            let isLive = event.startDate <= now
            let timeText = isLive
                ? "noch \(max(Int(event.endDate.timeIntervalSince(now) / 60), 0)) Min."
                : Self.startText(event.startDate, now: now)
            lecture = Lecture(
                moduleID: module.id,
                moduleName: module.name,
                location: event.location,
                isLive: isLive,
                timeText: timeText,
                progress: isLive ? calendar.progress(of: event) : 0
            )
        } else {
            lecture = nil
        }
        self.dueCards = dueCards
    }

    /// The timer's status, `nil` while it is idle.
    @MainActor
    static func status(of timer: StudyTimerViewModel) -> StudyTimerStatus? {
        guard timer.isActive else { return nil }
        return StudyTimerStatus(
            phaseTitle: timer.timer.phase.title, remainingText: timer.remainingText, isRunning: timer.timer.isRunning
        )
    }

    static func startText(_ start: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = start.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(start, inSameDayAs: now) { return "um \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(start, inSameDayAs: tomorrow) {
            return "morgen \(time)"
        }
        return start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
