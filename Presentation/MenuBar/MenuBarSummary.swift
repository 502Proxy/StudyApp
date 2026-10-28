import Foundation

/// What the menu bar item shows: the running lecture with remaining time, otherwise the next one,
/// and the due flashcards. Pure, so it is easy to test.
struct MenuBarSummary: Equatable {
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

    /// Short text next to the menu bar icon; empty when nothing is going on.
    var title: String {
        guard let lecture, lecture.isLive else { return "" }
        return lecture.timeText.replacingOccurrences(of: "noch ", with: "")
    }

    init(lecture: Lecture?, dueCards: Int) {
        self.lecture = lecture
        self.dueCards = dueCards
    }

    @MainActor
    init(calendar: StudyCalendarViewModel, dueCards: Int) {
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

    static func startText(_ start: Date, now: Date, calendar: Calendar = .current) -> String {
        let time = start.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(start, inSameDayAs: now) { return "um \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(start, inSameDayAs: tomorrow) {
            return "morgen \(time)"
        }
        return start.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
