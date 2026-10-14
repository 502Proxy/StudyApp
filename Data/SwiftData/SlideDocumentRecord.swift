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

    init(id: UUID, moduleID: UUID, title: String, fileName: String, pageCount: Int, importedAt: Date) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.fileName = fileName
        self.pageCount = pageCount
        self.importedAt = importedAt
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
            importedAt: document.importedAt
        )
    }

    func toDomain() -> SlideDocument {
        SlideDocument(
            id: id,
            moduleID: moduleID,
            title: title,
            fileName: fileName,
            pageCount: pageCount,
            importedAt: importedAt
        )
    }

    func apply(_ document: SlideDocument) {
        title = document.title
    }
}
