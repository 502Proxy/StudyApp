import Foundation
import SwiftData

@Model
final class CalendarSourceRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var urlString: String?
    var lastSyncedAt: Date?
    var kindRaw: String

    init(id: UUID, name: String, urlString: String?, lastSyncedAt: Date?, kindRaw: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.lastSyncedAt = lastSyncedAt
        self.kindRaw = kindRaw
    }

    convenience init(_ source: CalendarSource) {
        self.init(id: source.id, name: source.name, urlString: source.url?.absoluteString,
                  lastSyncedAt: source.lastSyncedAt, kindRaw: source.kind.rawValue)
    }

    func toDomain() -> CalendarSource {
        CalendarSource(id: id, name: name, url: urlString.flatMap(URL.init(string:)),
                       lastSyncedAt: lastSyncedAt, kind: CalendarSourceKind(rawValue: kindRaw) ?? .file)
    }
}

@Model
final class StudyCalendarEventRecord {
    @Attribute(.unique) var id: UUID
    var externalID: String
    var sourceID: UUID
    var title: String
    var details: String
    var location: String
    var startDate: Date
    var endDate: Date
    var moduleID: UUID?
    /// Mit Standardwert, damit bestehende Datenbanken per leichtgewichtiger Migration übernommen werden.
    var isAllDay: Bool = false

    init(id: UUID, externalID: String, sourceID: UUID, title: String, details: String,
         location: String, startDate: Date, endDate: Date, moduleID: UUID?, isAllDay: Bool = false) {
        self.id = id
        self.externalID = externalID
        self.sourceID = sourceID
        self.title = title
        self.details = details
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.moduleID = moduleID
        self.isAllDay = isAllDay
    }

    convenience init(_ event: StudyCalendarEvent) {
        self.init(id: event.id, externalID: event.externalID, sourceID: event.sourceID,
                  title: event.title, details: event.details, location: event.location,
                  startDate: event.startDate, endDate: event.endDate, moduleID: event.moduleID,
                  isAllDay: event.isAllDay)
    }

    func toDomain() -> StudyCalendarEvent {
        StudyCalendarEvent(id: id, externalID: externalID, sourceID: sourceID, title: title,
                           details: details, location: location, startDate: startDate,
                           endDate: endDate, moduleID: moduleID, isAllDay: isAllDay)
    }
}
