import Foundation

enum SlideError: Error, Equatable, LocalizedError {
    case emptyTitle
    case notFound
    case invalidPDF(String)

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Der Titel darf nicht leer sein."
        case .notFound: "Die Folien wurden nicht gefunden."
        case .invalidPDF(let name): "„\(name)“ ist keine lesbare PDF-Datei."
        }
    }
}

/// Zugriff auf die Metadaten importierter Folien. Die Dateien selbst liegen im `FileStorage`.
@MainActor
protocol SlideDocumentRepository {
    func documents(forModule moduleID: UUID) throws -> [SlideDocument]
    func add(_ document: SlideDocument) throws
    func update(_ document: SlideDocument) throws
    func delete(id: UUID) throws
}
