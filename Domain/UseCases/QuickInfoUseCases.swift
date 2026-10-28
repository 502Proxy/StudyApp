import Foundation

/// Short answers for Shortcuts and Siri: the next lecture and the due flashcards.
@MainActor
struct NextLectureUseCase {
    struct Answer: Equatable {
        let event: StudyCalendarEvent
        let module: StudyModule
    }

    let calendar: any StudyCalendarRepository
    let modules: any ModuleRepository

    /// The next (or running) event of an active module.
    func callAsFunction(now: Date) throws -> Answer? {
        let active = Dictionary(uniqueKeysWithValues: try modules.all().filter { !$0.isArchived }.map { ($0.id, $0) })
        let event = try calendar.events()
            .filter { !$0.isAllDay && $0.moduleID.map { active[$0] != nil } == true }
            .upcoming(after: now, limit: 1)
            .first
        guard let event, let moduleID = event.moduleID, let module = active[moduleID] else { return nil }
        return Answer(event: event, module: module)
    }

    static func text(_ answer: Answer?, now: Date, calendar: Calendar = .current) -> String {
        guard let answer else { return "Es steht keine Vorlesung an." }
        let event = answer.event
        let place = event.location.isEmpty ? "" : " in \(event.location)"
        if event.startDate <= now {
            let minutes = max(Int(event.endDate.timeIntervalSince(now) / 60), 0)
            return "\(answer.module.name) läuft gerade\(place), noch \(minutes) Minuten."
        }
        let time = event.startDate.formatted(date: .omitted, time: .shortened)
        let day: String
        if calendar.isDate(event.startDate, inSameDayAs: now) {
            day = "heute"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(event.startDate, inSameDayAs: tomorrow) {
            day = "morgen"
        } else {
            day = event.startDate.formatted(.dateTime.weekday(.wide))
        }
        return "Als Nächstes: \(answer.module.name), \(day) um \(time)\(place)."
    }
}

/// Due flashcards per active module, most first.
@MainActor
struct DueCardsUseCase {
    struct Count: Equatable {
        let module: StudyModule
        let due: Int
    }

    let modules: any ModuleRepository
    let flashcards: any FlashcardRepository

    func callAsFunction(now: Date) throws -> [Count] {
        try modules.all()
            .filter { !$0.isArchived }
            .map { module in Count(module: module, due: try flashcards.cards(forModule: module.id).filter { $0.isDue(at: now) }.count) }
            .filter { $0.due > 0 }
            .sorted { $0.due > $1.due }
    }

    static func text(_ counts: [Count]) -> String {
        let total = counts.reduce(0) { $0 + $1.due }
        guard total > 0 else { return "Keine Karteikarten fällig." }
        let details = counts.prefix(3).map { "\($0.module.name) \($0.due)" }.joined(separator: ", ")
        return "\(total) \(total == 1 ? "Karte" : "Karten") fällig: \(details)."
    }
}
