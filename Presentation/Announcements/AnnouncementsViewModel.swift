import Foundation
import Observation

/// An announcement together with its module, for display.
struct AnnouncementItem: Identifiable, Hashable {
    let announcement: CourseAnnouncement
    let module: StudyModule

    var id: String { announcement.id }
}

/// Stud.IP announcements of all modules; shared by „Heute“ and the module overview.
@MainActor
@Observable
final class AnnouncementsViewModel {
    private(set) var items: [AnnouncementItem] = []
    /// The announcement shown in the detail sheet.
    var selected: AnnouncementItem?
    var errorMessage: String?

    private let repository: any AnnouncementRepository
    private let modules: any ModuleRepository

    init(repository: any AnnouncementRepository, modules: any ModuleRepository) {
        self.repository = repository
        self.modules = modules
    }

    var unread: [AnnouncementItem] { items.filter { !$0.announcement.isRead } }

    func items(forModule moduleID: UUID) -> [AnnouncementItem] {
        items.filter { $0.module.id == moduleID }
    }

    func load() {
        do {
            let byID = Dictionary(uniqueKeysWithValues: try modules.all().map { ($0.id, $0) })
            items = try repository.all().compactMap { announcement in
                byID[announcement.moduleID].map { AnnouncementItem(announcement: announcement, module: $0) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Shows the full text and marks the announcement as read.
    func open(_ item: AnnouncementItem) {
        selected = item
        markRead([item])
    }

    func markRead(_ items: [AnnouncementItem]) {
        let ids = Set(items.filter { !$0.announcement.isRead }.map(\.id))
        guard !ids.isEmpty else { return }
        do {
            try repository.markRead(ids: ids)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
