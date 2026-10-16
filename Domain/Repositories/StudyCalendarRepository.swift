import Foundation

@MainActor
protocol StudyCalendarRepository {
    func events() throws -> [StudyCalendarEvent]
    func sources() throws -> [CalendarSource]
    func save(source: CalendarSource) throws
    func upsert(events: [StudyCalendarEvent]) throws
    func updateModuleLink(eventID: UUID, moduleID: UUID?) throws
    func deleteSource(id: UUID) throws
}
