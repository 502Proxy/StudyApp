import Foundation

enum StudyCalendarError: LocalizedError {
    case invalidSubscriptionURL
    case invalidCalendarData
    case sourceNotFound
    case emptyCalendar

    var errorDescription: String? {
        switch self {
        case .invalidSubscriptionURL: "Bitte gib eine gültige http- oder https-Kalender-URL ein."
        case .invalidCalendarData: "Die Datei enthält keine gültigen iCalendar-Termine. Unterstützt werden .ics-Dateien."
        case .sourceNotFound: "Die Kalenderquelle wurde nicht gefunden."
        case .emptyCalendar: "Der Kalender enthält keine importierbaren Termine."
        }
    }
}

@MainActor
struct ListStudyCalendarUseCase {
    let repository: any StudyCalendarRepository
    func callAsFunction() throws -> (events: [StudyCalendarEvent], sources: [CalendarSource]) {
        (try repository.events().sorted { $0.startDate < $1.startDate }, try repository.sources())
    }
}

@MainActor
struct ImportCalendarEventsUseCase {
    let repository: any StudyCalendarRepository
    func callAsFunction(source: CalendarSource, events: [StudyCalendarEvent]) throws {
        guard !events.isEmpty else { throw StudyCalendarError.emptyCalendar }
        try repository.save(source: source)
        try repository.upsert(events: events)
    }
}

@MainActor
struct LinkCalendarEventToModuleUseCase {
    let repository: any StudyCalendarRepository
    func callAsFunction(eventID: UUID, moduleID: UUID?) throws {
        try repository.updateModuleLink(eventID: eventID, moduleID: moduleID)
    }
}
