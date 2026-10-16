import Foundation

struct StudyCalendarEvent: Identifiable, Hashable, Sendable {
    let id: UUID
    var externalID: String
    var sourceID: UUID
    var title: String
    var details: String
    var location: String
    var startDate: Date
    var endDate: Date
    var moduleID: UUID?
}

struct CalendarSource: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var url: URL?
    var lastSyncedAt: Date?
    var kind: CalendarSourceKind
}

enum CalendarSourceKind: String, Codable, Sendable {
    case file
    case subscription
}
