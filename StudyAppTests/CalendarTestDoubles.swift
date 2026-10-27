import Foundation
@testable import StudyApp

/// Calendar repository that, like SwiftData, keeps one event per ID.
@MainActor
final class InMemoryCalendarRepository: StudyCalendarRepository {
    var storedEvents: [StudyCalendarEvent] = []
    var storedSources: [CalendarSource] = []

    func events() throws -> [StudyCalendarEvent] { storedEvents }
    func sources() throws -> [CalendarSource] { storedSources }

    func save(source: CalendarSource) throws {
        storedSources.removeAll { $0.id == source.id }
        storedSources.append(source)
    }

    func replaceEvents(forSource sourceID: UUID, with events: [StudyCalendarEvent]) throws {
        storedEvents.removeAll { $0.sourceID == sourceID }
        storedEvents += events
    }

    func updateModuleLink(eventID: UUID, moduleID: UUID?) throws {
        try updateModuleLinks(eventIDs: [eventID], moduleID: moduleID)
    }

    func updateModuleLinks(eventIDs: [UUID], moduleID: UUID?) throws {
        for index in storedEvents.indices where eventIDs.contains(storedEvents[index].id) {
            storedEvents[index].moduleID = moduleID
        }
    }

    func clearModuleLinks(forModule moduleID: UUID) throws {
        for index in storedEvents.indices where storedEvents[index].moduleID == moduleID {
            storedEvents[index].moduleID = nil
        }
    }

    func deleteSource(id: UUID) throws {
        storedEvents.removeAll { $0.sourceID == id }
        storedSources.removeAll { $0.id == id }
    }
}
