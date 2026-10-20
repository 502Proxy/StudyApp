import Foundation
import SwiftData

@MainActor
final class SwiftDataStudyCalendarRepository: StudyCalendarRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func events() throws -> [StudyCalendarEvent] {
        try context.fetch(FetchDescriptor<StudyCalendarEventRecord>()).map { $0.toDomain() }
    }

    func sources() throws -> [CalendarSource] {
        try context.fetch(FetchDescriptor<CalendarSourceRecord>()).map { $0.toDomain() }
    }

    func save(source: CalendarSource) throws {
        let sourceID = source.id
        let descriptor = FetchDescriptor<CalendarSourceRecord>(predicate: #Predicate { $0.id == sourceID })

        if let existing = try context.fetch(descriptor).first {
            existing.name = source.name
            existing.urlString = source.url?.absoluteString
            existing.lastSyncedAt = source.lastSyncedAt
            existing.kindRaw = source.kind.rawValue
        } else {
            context.insert(CalendarSourceRecord(source))
        }
        try context.save()
    }

    func replaceEvents(forSource sourceID: UUID, with events: [StudyCalendarEvent]) throws {
        let descriptor = FetchDescriptor<StudyCalendarEventRecord>(predicate: #Predicate { $0.sourceID == sourceID })
        var stored: [String: StudyCalendarEventRecord] = [:]
        for record in try context.fetch(descriptor) {
            if stored[record.externalID] == nil {
                stored[record.externalID] = record
            } else {
                context.delete(record) // Duplikat aus früheren Importen
            }
        }

        var kept = Set<String>()
        for event in events where kept.insert(event.externalID).inserted {
            if let record = stored[event.externalID] {
                record.title = event.title
                record.details = event.details
                record.location = event.location
                record.startDate = event.startDate
                record.endDate = event.endDate
                record.isAllDay = event.isAllDay
                // Die Modulzuordnung der Nutzerin bzw. des Nutzers bleibt bewusst unverändert.
            } else {
                context.insert(StudyCalendarEventRecord(event))
            }
        }
        for (externalID, record) in stored where !kept.contains(externalID) {
            context.delete(record)
        }
        try context.save()
    }

    func updateModuleLink(eventID: UUID, moduleID: UUID?) throws {
        let id = eventID
        let descriptor = FetchDescriptor<StudyCalendarEventRecord>(predicate: #Predicate { $0.id == id })
        guard let event = try context.fetch(descriptor).first else { return }
        event.moduleID = moduleID
        try context.save()
    }

    func updateModuleLinks(eventIDs: [UUID], moduleID: UUID?) throws {
        let ids = Set(eventIDs)
        guard !ids.isEmpty else { return }
        var changed = false
        for event in try context.fetch(FetchDescriptor<StudyCalendarEventRecord>()) where ids.contains(event.id) {
            if event.moduleID != moduleID {
                event.moduleID = moduleID
                changed = true
            }
        }
        if changed { try context.save() }
    }

    func clearModuleLinks(forModule moduleID: UUID) throws {
        let id: UUID? = moduleID
        let descriptor = FetchDescriptor<StudyCalendarEventRecord>(predicate: #Predicate { $0.moduleID == id })
        let linked = try context.fetch(descriptor)
        guard !linked.isEmpty else { return }
        for event in linked {
            event.moduleID = nil
        }
        try context.save()
    }

    func deleteSource(id: UUID) throws {
        let sourceID = id
        let eventDescriptor = FetchDescriptor<StudyCalendarEventRecord>(predicate: #Predicate { $0.sourceID == sourceID })
        for event in try context.fetch(eventDescriptor) {
            context.delete(event)
        }
        let sourceDescriptor = FetchDescriptor<CalendarSourceRecord>(predicate: #Predicate { $0.id == sourceID })
        for source in try context.fetch(sourceDescriptor) {
            context.delete(source)
        }
        try context.save()
    }
}
