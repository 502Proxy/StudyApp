import Foundation

/// Eine Aufgabe oder Abgabe eines Moduls, z. B. „Übungsblatt 3“ mit Abgabe am Freitag, 12:00 Uhr.
struct Assignment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let moduleID: UUID
    var title: String
    var details: String
    var dueDate: Date
    var completedAt: Date?
    let createdAt: Date

    var isCompleted: Bool { completedAt != nil }

    init(
        id: UUID = UUID(),
        moduleID: UUID,
        title: String,
        details: String = "",
        dueDate: Date,
        completedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.details = details
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.createdAt = createdAt
    }

    func isOverdue(at date: Date) -> Bool {
        !isCompleted && dueDate < date
    }
}

/// Dringlichkeit einer offenen Aufgabe, für Farben und Gruppierung.
enum AssignmentUrgency: Int, Comparable, Sendable {
    case overdue
    case today
    case soon
    case later
    case done

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Assignment {
    /// „Bald“ heißt: innerhalb der nächsten `soonDays` Tage fällig.
    func urgency(at date: Date, calendar: Calendar = .current, soonDays: Int = 3) -> AssignmentUrgency {
        if isCompleted { return .done }
        if dueDate < date { return .overdue }
        if calendar.isDate(dueDate, inSameDayAs: date) { return .today }
        if let limit = calendar.date(byAdding: .day, value: soonDays, to: calendar.startOfDay(for: date)), dueDate < limit {
            return .soon
        }
        return .later
    }

    /// Offene zuerst nach Fälligkeit, erledigte danach (zuletzt erledigte oben).
    static func displayOrder(_ lhs: Assignment, _ rhs: Assignment) -> Bool {
        switch (lhs.completedAt, rhs.completedAt) {
        case (nil, nil): return lhs.dueDate == rhs.dueDate ? lhs.createdAt < rhs.createdAt : lhs.dueDate < rhs.dueDate
        case (nil, _?): return true
        case (_?, nil): return false
        case let (left?, right?): return left > right
        }
    }
}
