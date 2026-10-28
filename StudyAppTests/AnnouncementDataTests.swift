import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
struct SwiftDataAnnouncementRepositoryTests {
    @Test func upsertKeepsOneRecordPerIDAndSortsNewestFirst() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataAnnouncementRepository(context: container.mainContext)
            let module = UUID()
            let older = CourseAnnouncement(
                id: "n1", moduleID: module, title: "Alt", body: "", publishedAt: Date(timeIntervalSince1970: 100), isRead: false
            )
            let newer = CourseAnnouncement(
                id: "n2", moduleID: module, title: "Neu", body: "", publishedAt: Date(timeIntervalSince1970: 200), isRead: false
            )

            try repository.upsert([older, newer])
            var changed = older
            changed.title = "Alt (geändert)"
            try repository.upsert([changed])

            #expect(try repository.announcements(forModule: module).map(\.title) == ["Neu", "Alt (geändert)"])
        }
    }

    @Test func markReadAndCleanupByModule() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataAnnouncementRepository(context: container.mainContext)
            let kept = UUID()
            let removed = UUID()
            try repository.upsert([
                CourseAnnouncement(id: "a", moduleID: kept, title: "A", body: "", publishedAt: .now, isRead: false),
                CourseAnnouncement(id: "b", moduleID: removed, title: "B", body: "", publishedAt: .now, isRead: false),
            ])

            try repository.markRead(ids: ["a"])
            try repository.deleteAll(exceptModules: [kept])

            let all = try repository.all()
            #expect(all.map(\.id) == ["a"])
            #expect(all.first?.isRead == true)
        }
    }
}
