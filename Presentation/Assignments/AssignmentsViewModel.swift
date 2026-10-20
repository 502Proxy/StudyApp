import Foundation
import Observation

/// Eingabewerte des Aufgaben-Editors.
struct AssignmentDraft: Identifiable {
    let id = UUID()
    var assignmentID: UUID?
    var moduleID: UUID?
    var title = ""
    var details = ""
    var dueDate: Date

    var isNew: Bool { assignmentID == nil }

    init(assignment: Assignment) {
        assignmentID = assignment.id
        moduleID = assignment.moduleID
        title = assignment.title
        details = assignment.details
        dueDate = assignment.dueDate
    }

    /// Neue Aufgabe, standardmäßig in einer Woche um 12:00 Uhr fällig.
    init(moduleID: UUID?, now: Date = Date(), calendar: Calendar = .current) {
        self.moduleID = moduleID
        let inAWeek = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        dueDate = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: inAWeek) ?? inAWeek
    }
}

/// Alle Aufgaben der App an einem Ort, damit Modul, Startseite und Kalender denselben Stand zeigen.
@MainActor
@Observable
final class AssignmentsViewModel {
    private(set) var assignments: [Assignment] = []
    private(set) var referenceDate: Date
    var editor: AssignmentDraft?
    var errorMessage: String?

    let calendar: Calendar
    private let now: () -> Date
    private let listAssignments: ListAssignmentsUseCase
    private let saveAssignment: SaveAssignmentUseCase
    private let setCompletion: SetAssignmentCompletionUseCase
    private let deleteAssignment: DeleteAssignmentUseCase

    init(repository: any AssignmentRepository, calendar: Calendar = .current, now: @escaping () -> Date = { .now }) {
        self.calendar = calendar
        self.now = now
        referenceDate = now()
        listAssignments = ListAssignmentsUseCase(repository: repository)
        saveAssignment = SaveAssignmentUseCase(repository: repository, now: now)
        setCompletion = SetAssignmentCompletionUseCase(repository: repository, now: now)
        deleteAssignment = DeleteAssignmentUseCase(repository: repository)
    }

    // MARK: Abfragen

    func assignments(forModule moduleID: UUID) -> [Assignment] {
        assignments.filter { $0.moduleID == moduleID }
    }

    func openCount(forModule moduleID: UUID) -> Int {
        assignments.lazy.filter { $0.moduleID == moduleID && !$0.isCompleted }.count
    }

    /// Überfällige und in den nächsten `days` Tagen fällige offene Aufgaben, für „Heute“.
    func upcoming(days: Int = 7) -> [Assignment] {
        let limit = calendar.date(byAdding: .day, value: days + 1, to: calendar.startOfDay(for: referenceDate)) ?? referenceDate
        return assignments.filter { !$0.isCompleted && $0.dueDate < limit }
    }

    var overdueCount: Int {
        assignments.lazy.filter { $0.isOverdue(at: self.referenceDate) }.count
    }

    /// Aufgaben, die an `day` fällig sind (für den Kalender).
    func assignments(on day: Date) -> [Assignment] {
        assignments.filter { calendar.isDate($0.dueDate, inSameDayAs: day) }
    }

    func urgency(of assignment: Assignment) -> AssignmentUrgency {
        assignment.urgency(at: referenceDate, calendar: calendar)
    }

    func dueText(for assignment: Assignment) -> String {
        AssignmentFormatting.dueText(for: assignment, at: referenceDate, calendar: calendar)
    }

    // MARK: Aktionen

    func load() {
        referenceDate = now()
        do {
            assignments = try listAssignments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tick() {
        referenceDate = now()
    }

    func startNewAssignment(moduleID: UUID?) {
        editor = AssignmentDraft(moduleID: moduleID, now: referenceDate, calendar: calendar)
    }

    func edit(_ assignment: Assignment) {
        editor = AssignmentDraft(assignment: assignment)
    }

    /// Speichert den Entwurf. Bei einem Fehler bleibt der Editor offen.
    @discardableResult
    func save(_ draft: AssignmentDraft) -> Bool {
        guard let moduleID = draft.moduleID else {
            errorMessage = "Bitte wähle ein Modul für die Aufgabe."
            return false
        }
        do {
            try saveAssignment(
                id: draft.assignmentID,
                moduleID: moduleID,
                title: draft.title,
                details: draft.details,
                dueDate: draft.dueDate
            )
            load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func setCompleted(_ assignment: Assignment, _ isCompleted: Bool) {
        do {
            try setCompletion(assignment, isCompleted: isCompleted)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ assignment: Assignment) {
        do {
            try deleteAssignment(id: assignment.id)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Lesbare Fälligkeit, z. B. „heute, 12:00“, „morgen, 23:59“, „in 5 Tagen“, „seit 2 Tagen überfällig“.
enum AssignmentFormatting {
    static func dueText(for assignment: Assignment, at reference: Date, calendar: Calendar = .current) -> String {
        let due = assignment.dueDate
        let time = timeText(due, calendar: calendar)
        if let completedAt = assignment.completedAt {
            return "erledigt am \(dayText(completedAt, calendar: calendar))"
        }
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: reference),
            to: calendar.startOfDay(for: due)
        ).day ?? 0

        if due < reference {
            switch days {
            case 0: return "heute, \(time) – überfällig"
            case -1: return "seit gestern überfällig"
            default: return "seit \(-days) Tagen überfällig"
            }
        }
        switch days {
        case 0: return "heute, \(time)"
        case 1: return "morgen, \(time)"
        case 2...6: return "in \(days) Tagen · \(weekdayText(due, calendar: calendar)), \(time)"
        default: return "\(dayText(due, calendar: calendar)), \(time)"
        }
    }

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = format
        return formatter
    }

    private static func timeText(_ date: Date, calendar: Calendar) -> String {
        formatter("HH:mm", calendar: calendar).string(from: date)
    }

    private static func weekdayText(_ date: Date, calendar: Calendar) -> String {
        formatter("EEE", calendar: calendar).string(from: date)
    }

    private static func dayText(_ date: Date, calendar: Calendar) -> String {
        formatter("d. MMM", calendar: calendar).string(from: date)
    }
}
