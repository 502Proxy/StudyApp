import Foundation
import SwiftData

@MainActor
final class SwiftDataAnnouncementRepository: AnnouncementRepository {
    private let context: ModelContext
    init(context: ModelContext) { self.context = context }

    func all() throws -> [CourseAnnouncement] {
        let descriptor = FetchDescriptor<AnnouncementRecord>(sortBy: [SortDescriptor(\.publishedAt, order: .reverse)])
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func announcements(forModule moduleID: UUID) throws -> [CourseAnnouncement] {
        let descriptor = FetchDescriptor<AnnouncementRecord>(
            predicate: #Predicate { $0.moduleID == moduleID },
            sortBy: [SortDescriptor(\.publishedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toDomain() }
    }

    func upsert(_ announcements: [CourseAnnouncement]) throws {
        guard !announcements.isEmpty else { return }
        let existing = Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<AnnouncementRecord>()).map { ($0.id, $0) }
        )
        for announcement in announcements {
            if let record = existing[announcement.id] {
                record.apply(announcement)
            } else {
                context.insert(AnnouncementRecord(announcement))
            }
        }
        try context.save()
    }

    func markRead(ids: Set<String>) throws {
        let records = try context.fetch(FetchDescriptor<AnnouncementRecord>()).filter { ids.contains($0.id) && !$0.isRead }
        guard !records.isEmpty else { return }
        for record in records { record.isRead = true }
        try context.save()
    }

    func deleteAll(exceptModules moduleIDs: Set<UUID>) throws {
        let records = try context.fetch(FetchDescriptor<AnnouncementRecord>()).filter { !moduleIDs.contains($0.moduleID) }
        guard !records.isEmpty else { return }
        for record in records { context.delete(record) }
        try context.save()
    }
}
