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

        let descriptor = FetchDescriptor<CalendarSourceRecord>(
            predicate: #Predicate { record in
                record.id == sourceID
            }
        )

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

    func updateModuleLink(eventID: UUID, moduleID: UUID?) throws {
        let id = eventID

        let descriptor = FetchDescriptor<StudyCalendarEventRecord>(
            predicate: #Predicate { record in
                record.id == id
            }
        )

        guard let event = try context.fetch(descriptor).first else {
            return
        }

        event.moduleID = moduleID
        try context.save()
    }

    func deleteSource(id: UUID) throws {
        let sourceID = id

        let eventDescriptor = FetchDescriptor<StudyCalendarEventRecord>(
            predicate: #Predicate { record in
                record.sourceID == sourceID
            }
        )

        for event in try context.fetch(eventDescriptor) {
            context.delete(event)
        }

        let sourceDescriptor = FetchDescriptor<CalendarSourceRecord>(
            predicate: #Predicate { record in
                record.id == sourceID
            }
        )

        for source in try context.fetch(sourceDescriptor) {
            context.delete(source)
        }

        try context.save()
    }

    func upsert(events: [StudyCalendarEvent]) throws {
        let existing = try context.fetch(FetchDescriptor<StudyCalendarEventRecord>())
        var index: [String: StudyCalendarEventRecord] = [:]
        for record in existing {
            let key = "\(record.sourceID.uuidString)|\(record.externalID)"
            if index[key] == nil { index[key] = record }
        }
        for event in events {
            let key = "\(event.sourceID.uuidString)|\(event.externalID)"
            if let record = index[key] {
                record.title = event.title
                record.details = event.details
                record.location = event.location
                record.startDate = event.startDate
                record.endDate = event.endDate
                // Keep a user's existing module assignment on refresh.
            } else {
                context.insert(StudyCalendarEventRecord(event))
            }
        }
        try context.save()
    }


}
