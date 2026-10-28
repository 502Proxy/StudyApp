import Foundation
import SwiftData

@MainActor
final class SwiftDataStudySessionRepository: StudySessionRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all() throws -> [StudySession] {
        let descriptor = FetchDescriptor<StudySessionRecord>(sortBy: [SortDescriptor(\.startedAt)])
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func add(_ session: StudySession) throws {
        context.insert(StudySessionRecord(session))
        try context.save()
    }

    func deleteSessions(forModule moduleID: UUID) throws {
        let records = try context.fetch(FetchDescriptor<StudySessionRecord>()).filter { $0.moduleID == moduleID }
        guard !records.isEmpty else { return }
        for record in records { context.delete(record) }
        try context.save()
    }

    func deleteAll() throws {
        try context.delete(model: StudySessionRecord.self)
        try context.save()
    }
}
