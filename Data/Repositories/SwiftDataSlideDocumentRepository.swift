import Foundation
import SwiftData

@MainActor
final class SwiftDataSlideDocumentRepository: SlideDocumentRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func documents(forModule moduleID: UUID) throws -> [SlideDocument] {
        let descriptor = FetchDescriptor<SlideDocumentRecord>(
            predicate: #Predicate { $0.moduleID == moduleID },
            sortBy: [SortDescriptor(\.importedAt)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func add(_ document: SlideDocument) throws {
        context.insert(SlideDocumentRecord(document))
        try context.save()
    }

    func update(_ document: SlideDocument) throws {
        guard let record = try record(for: document.id) else { throw SlideError.notFound }
        record.apply(document)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try record(for: id) else { throw SlideError.notFound }
        context.delete(record)
        try context.save()
    }

    private func record(for id: UUID) throws -> SlideDocumentRecord? {
        var descriptor = FetchDescriptor<SlideDocumentRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
