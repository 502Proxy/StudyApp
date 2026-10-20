import Foundation

@MainActor
struct ListAssignmentsUseCase {
    let repository: any AssignmentRepository

    func callAsFunction(moduleID: UUID? = nil) throws -> [Assignment] {
        try repository.all()
            .filter { moduleID == nil || $0.moduleID == moduleID }
            .sorted(by: Assignment.displayOrder)
    }
}

/// Legt eine Aufgabe an oder ändert sie. Der Titel wird bereinigt und darf nicht leer sein.
@MainActor
struct SaveAssignmentUseCase {
    let repository: any AssignmentRepository
    var now: () -> Date = { Date() }

    @discardableResult
    func callAsFunction(
        id: UUID? = nil,
        moduleID: UUID,
        title: String,
        details: String,
        dueDate: Date
    ) throws -> Assignment {
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty else { throw AssignmentError.emptyTitle }

        if let id {
            guard var existing = try repository.all().first(where: { $0.id == id }) else {
                throw AssignmentError.notFound
            }
            existing.title = cleanTitle
            existing.details = details.trimmed
            existing.dueDate = dueDate
            try repository.update(existing)
            return existing
        }

        let assignment = Assignment(
            moduleID: moduleID,
            title: cleanTitle,
            details: details.trimmed,
            dueDate: dueDate,
            createdAt: now()
        )
        try repository.add(assignment)
        return assignment
    }
}

@MainActor
struct SetAssignmentCompletionUseCase {
    let repository: any AssignmentRepository
    var now: () -> Date = { Date() }

    @discardableResult
    func callAsFunction(_ assignment: Assignment, isCompleted: Bool) throws -> Assignment {
        var updated = assignment
        updated.completedAt = isCompleted ? (assignment.completedAt ?? now()) : nil
        guard updated != assignment else { return assignment }
        try repository.update(updated)
        return updated
    }
}

@MainActor
struct DeleteAssignmentUseCase {
    let repository: any AssignmentRepository

    func callAsFunction(id: UUID) throws {
        try repository.delete(id: id)
    }
}
