import Foundation
import SwiftData

@Model
final class AssignmentRecord {
    @Attribute(.unique) var id: UUID
    var moduleID: UUID
    var title: String
    var details: String
    var dueDate: Date
    var completedAt: Date?
    var createdAt: Date

    init(id: UUID, moduleID: UUID, title: String, details: String, dueDate: Date, completedAt: Date?, createdAt: Date) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.details = details
        self.dueDate = dueDate
        self.completedAt = completedAt
        self.createdAt = createdAt
    }
}

extension AssignmentRecord {
    convenience init(_ assignment: Assignment) {
        self.init(
            id: assignment.id,
            moduleID: assignment.moduleID,
            title: assignment.title,
            details: assignment.details,
            dueDate: assignment.dueDate,
            completedAt: assignment.completedAt,
            createdAt: assignment.createdAt
        )
    }

    func toDomain() -> Assignment {
        Assignment(
            id: id,
            moduleID: moduleID,
            title: title,
            details: details,
            dueDate: dueDate,
            completedAt: completedAt,
            createdAt: createdAt
        )
    }

    func apply(_ assignment: Assignment) {
        title = assignment.title
        details = assignment.details
        dueDate = assignment.dueDate
        completedAt = assignment.completedAt
    }
}
