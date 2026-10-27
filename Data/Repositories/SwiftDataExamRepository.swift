import Foundation
import SwiftData

@MainActor
final class SwiftDataExamRepository: ExamRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all() throws -> [Exam] {
        try context.fetch(FetchDescriptor<ExamRecord>()).map { $0.toDomain() }
    }

    func save(_ exam: Exam) throws {
        let id = exam.id
        if let record = try context.fetch(FetchDescriptor<ExamRecord>(predicate: #Predicate { $0.id == id })).first {
            record.apply(exam)
        } else {
            context.insert(ExamRecord(exam))
        }
        try context.save()
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<ExamRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { throw ExamError.notFound }
        context.delete(record)
        try context.save()
    }

    func deleteExams(forModule moduleID: UUID) throws {
        let records = try context.fetch(FetchDescriptor<ExamRecord>(predicate: #Predicate { $0.moduleID == moduleID }))
        guard !records.isEmpty else { return }
        for record in records { context.delete(record) }
        try context.save()
    }
}
