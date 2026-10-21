import Foundation
import SwiftData

/// SwiftData-Modell für Folien. Die Modulzugehörigkeit ist eine einfache ID,
/// das Aufräumen beim Löschen eines Moduls übernimmt der UseCase.
@Model
final class SlideDocumentRecord {
    @Attribute(.unique) var id: UUID
    var moduleID: UUID
    var title: String
    var fileName: String
    var pageCount: Int
    var importedAt: Date
    /// Optional, damit bestehende Datenbanken per leichtgewichtiger Migration übernommen werden.
    var remoteID: String?
    var remoteVersion: String?

    init(
        id: UUID, moduleID: UUID, title: String, fileName: String, pageCount: Int, importedAt: Date,
        remoteID: String? = nil, remoteVersion: String? = nil
    ) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.fileName = fileName
        self.pageCount = pageCount
        self.importedAt = importedAt
        self.remoteID = remoteID
        self.remoteVersion = remoteVersion
    }
}

extension SlideDocumentRecord {
    convenience init(_ document: SlideDocument) {
        self.init(
            id: document.id,
            moduleID: document.moduleID,
            title: document.title,
            fileName: document.fileName,
            pageCount: document.pageCount,
            importedAt: document.importedAt,
            remoteID: document.remoteID,
            remoteVersion: document.remoteVersion
        )
    }

    func toDomain() -> SlideDocument {
        SlideDocument(
            id: id,
            moduleID: moduleID,
            title: title,
            fileName: fileName,
            pageCount: pageCount,
            importedAt: importedAt,
            remoteID: remoteID,
            remoteVersion: remoteVersion
        )
    }

    func apply(_ document: SlideDocument) {
        title = document.title
    }
}
