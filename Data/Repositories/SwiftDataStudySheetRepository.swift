import Foundation
import SwiftData

@MainActor
final class SwiftDataStudySheetRepository: StudySheetRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func sheets(forModule moduleID: UUID) throws -> [StudySheet] {
        let descriptor = FetchDescriptor<StudySheetRecord>(
            predicate: #Predicate { $0.moduleID == moduleID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func add(_ sheet: StudySheet) throws {
        context.insert(StudySheetRecord(sheet))
        try context.save()
    }

    func update(_ sheet: StudySheet) throws {
        guard let record = try record(for: sheet.id) else { throw StudySheetError.notFound }
        record.apply(sheet)
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let record = try record(for: id) else { throw StudySheetError.notFound }
        context.delete(record)
        try context.save()
    }

    func deleteSheets(forModule moduleID: UUID) throws {
        let descriptor = FetchDescriptor<StudySheetRecord>(
            predicate: #Predicate { $0.moduleID == moduleID }
        )
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { return }
        for record in records {
            context.delete(record)
        }
        try context.save()
    }

    private func record(for id: UUID) throws -> StudySheetRecord? {
        var descriptor = FetchDescriptor<StudySheetRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
