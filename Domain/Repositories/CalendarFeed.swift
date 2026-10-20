import Foundation

/// Port: lädt die Rohdaten eines iCalendar-Feeds. Die Implementierung liegt in der Data-Schicht.
@MainActor
protocol CalendarFeedLoader {
    func load(from url: URL) async throws -> Data
}

/// Port: wandelt iCalendar-Daten in Termine einer Quelle um.
@MainActor
protocol CalendarEventParsing {
    func parse(_ data: Data, sourceID: UUID) throws -> [StudyCalendarEvent]
}
