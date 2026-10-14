import Foundation
import SwiftData

@MainActor
final class SwiftDataNoteRepository: NoteRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func notes(forSlideDocument slideDocumentID: UUID) throws -> [LectureNote] {
        let descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate { $0.slideDocumentID == slideDocumentID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func add(_ note: LectureNote) throws {
        context.insert(NoteRecord(note))
        try context.save()
    }

    func update(_ note: LectureNote) throws {
        guard let record = try record(for: note.id) else { throw NoteError.notFound }
        record.apply(note)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try record(for: id) else { throw NoteError.notFound }
        context.delete(record)
        try context.save()
    }

    func deleteNotes(forSlideDocument slideDocumentID: UUID) throws {
        let descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate { $0.slideDocumentID == slideDocumentID }
        )
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return }
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    private func record(for id: UUID) throws -> NoteRecord? {
        var descriptor = FetchDescriptor<NoteRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
