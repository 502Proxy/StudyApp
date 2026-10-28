import Foundation

struct StudyCalendarEvent: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var externalID: String
    var sourceID: UUID
    var title: String
    var details: String
    var location: String
    var startDate: Date
    /// Bei ganztägigen Terminen exklusiv (wie in iCalendar): Folgetag, 00:00 Uhr.
    var endDate: Date
    var moduleID: UUID?
    var isAllDay: Bool = false
}

struct CalendarSource: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var name: String
    var url: URL?
    var lastSyncedAt: Date?
    var kind: CalendarSourceKind
}

enum CalendarSourceKind: String, Codable, Sendable {
    case file
    case subscription
    /// Dates of linked courses, loaded from the Stud.IP JSON:API during a Stud.IP sync.
    case studIP
}

// MARK: - Zeitlogik

extension StudyCalendarEvent {
    /// Letzter Zeitpunkt, an dem der Termin noch läuft. Das Ende selbst gehört nicht mehr dazu,
    /// ein Termin bis 00:00 Uhr belegt den Folgetag also nicht.
    var lastActiveInstant: Date {
        endDate > startDate ? endDate.addingTimeInterval(-1) : startDate
    }

    /// Alle Kalendertage (jeweils Tagesbeginn), die der Termin berührt.
    /// Die Obergrenze schützt vor fehlerhaften Feeds mit absurd langen Terminen.
    func occupiedDays(calendar: Calendar = .current, limit: Int = 62) -> [Date] {
        let last = calendar.startOfDay(for: lastActiveInstant)
        var days: [Date] = []
        var day = calendar.startOfDay(for: startDate)
        while day <= last, days.count < limit {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Anzeigereihenfolge innerhalb eines Tages: ganztägig zuerst, dann nach Beginn und Titel.
    static func displayOrder(_ lhs: StudyCalendarEvent, _ rhs: StudyCalendarEvent) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

extension Sequence where Element == StudyCalendarEvent {
    /// Noch nicht beendete Termine ab `reference`, zeitlich sortiert; optional nur für ein Modul.
    func upcoming(after reference: Date, moduleID: UUID? = nil, limit: Int) -> [StudyCalendarEvent] {
        let matches = filter { event in
            (moduleID == nil || event.moduleID == moduleID) && event.lastActiveInstant >= reference
        }
        return Array(matches.sorted { $0.startDate < $1.startDate }.prefix(limit))
    }
}
