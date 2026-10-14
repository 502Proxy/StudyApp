import Foundation
import SwiftData

@MainActor
final class SwiftDataFlashcardRepository: FlashcardRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func cards(forModule moduleID: UUID) throws -> [Flashcard] {
        let descriptor = FetchDescriptor<FlashcardRecord>(
            predicate: #Predicate { $0.moduleID == moduleID },
            sortBy: [SortDescriptor(\.dueAt), SortDescriptor(\.createdAt)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func add(_ card: Flashcard) throws {
        context.insert(FlashcardRecord(card))
        try context.save()
    }

    func update(_ card: Flashcard) throws {
        guard let record = try record(for: card.id) else { throw FlashcardError.notFound }
        record.apply(card)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try record(for: id) else { throw FlashcardError.notFound }
        context.delete(record)
        try context.save()
    }

    func deleteCards(forModule moduleID: UUID) throws {
        let descriptor = FetchDescriptor<FlashcardRecord>(
            predicate: #Predicate { $0.moduleID == moduleID }
        )
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return }
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    private func record(for id: UUID) throws -> FlashcardRecord? {
        var descriptor = FetchDescriptor<FlashcardRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
