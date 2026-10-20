import Foundation
import SwiftData

@MainActor
final class SwiftDataModuleRepository: ModuleRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func all() throws -> [StudyModule] {
        let descriptor = FetchDescriptor<ModuleRecord>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func add(_ module: StudyModule) throws {
        context.insert(ModuleRecord(module))
        try context.save()
    }

    func update(_ module: StudyModule) throws {
        guard let record = try record(for: module.id) else { throw ModuleError.notFound }
        record.apply(module)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try record(for: id) else { throw ModuleError.notFound }
        context.delete(record)
        try context.save()
    }

    private func record(for id: UUID) throws -> ModuleRecord? {
        var descriptor = FetchDescriptor<ModuleRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
