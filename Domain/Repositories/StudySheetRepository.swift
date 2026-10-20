import Foundation

enum StudySheetError: Error, Equatable, LocalizedError {
    case emptyTitle
    case noSourceNotes
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Der Titel des Lernzettels darf nicht leer sein."
        case .noSourceNotes: "Wähle mindestens eine Notiz aus, um einen Lernzettel zu erstellen."
        case .notFound: "Der Lernzettel wurde nicht gefunden."
        }
    }
}

@MainActor
protocol StudySheetRepository {
    func sheets(forModule moduleID: UUID) throws -> [StudySheet]
    func add(_ sheet: StudySheet) throws
    func update(_ sheet: StudySheet) throws
    func delete(id: UUID) throws
    func deleteSheets(forModule moduleID: UUID) throws
}
