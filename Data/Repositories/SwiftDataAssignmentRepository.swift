import Foundation
import SwiftData

@MainActor
final class SwiftDataAssignmentRepository: AssignmentRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() throws -> [Assignment] {
        let descriptor = FetchDescriptor<AssignmentRecord>(sortBy: [SortDescriptor(\.dueDate)])
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func add(_ assignment: Assignment) throws {
        context.insert(AssignmentRecord(assignment))
        try context.save()
    }

    func update(_ assignment: Assignment) throws {
        guard let record = try record(for: assignment.id) else { throw AssignmentError.notFound }
        record.apply(assignment)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try record(for: id) else { throw AssignmentError.notFound }
        context.delete(record)
        try context.save()
    }

    func deleteAssignments(forModule moduleID: UUID) throws {
        let descriptor = FetchDescriptor<AssignmentRecord>(predicate: #Predicate { $0.moduleID == moduleID })
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return }
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    private func record(for id: UUID) throws -> AssignmentRecord? {
        var descriptor = FetchDescriptor<AssignmentRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
