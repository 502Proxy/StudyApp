import Foundation

/// Where a search result leads. Encoded in the Spotlight item identifier, so a click on a result can be
/// turned back into navigation without a lookup table.
enum SearchTarget: Hashable, Sendable {
    case module(UUID)
    case note(moduleID: UUID, noteID: UUID)
    case studySheet(moduleID: UUID, sheetID: UUID)

    var identifier: String {
        switch self {
        case .module(let id): "module/\(id.uuidString)"
        case .note(let moduleID, let noteID): "note/\(moduleID.uuidString)/\(noteID.uuidString)"
        case .studySheet(let moduleID, let sheetID): "sheet/\(moduleID.uuidString)/\(sheetID.uuidString)"
        }
    }

    init?(identifier: String) {
        let parts = identifier.split(separator: "/").map(String.init)
        let ids = parts.dropFirst().compactMap(UUID.init(uuidString:))
        guard ids.count == parts.count - 1 else { return nil }
        switch (parts.first, ids.count) {
        case ("module", 1): self = .module(ids[0])
        case ("note", 2): self = .note(moduleID: ids[0], noteID: ids[1])
        case ("sheet", 2): self = .studySheet(moduleID: ids[0], sheetID: ids[1])
        default: return nil
        }
    }
}

/// One entry for the system search.
struct SearchableItem: Equatable, Sendable {
    let target: SearchTarget
    let title: String
    /// Text Spotlight searches and previews.
    let content: String
    /// e.g. „Notiz · Analysis I“.
    let subtitle: String
    let modifiedAt: Date?
}

/// Port to the system search index (Core Spotlight).
@MainActor
protocol SearchIndexing {
    /// Replaces everything StudyApp has indexed with `items`.
    func replaceAll(with items: [SearchableItem]) async throws
}
