import Foundation

enum FlashcardError: Error, Equatable, LocalizedError {
    case emptyQuestion
    case emptyAnswer
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyQuestion: "Die Vorderseite darf nicht leer sein."
        case .emptyAnswer: "Die Antwort darf nicht leer sein."
        case .notFound: "Die Karteikarte wurde nicht gefunden."
        }
    }
}

@MainActor
protocol FlashcardRepository {
    func cards(forModule moduleID: UUID) throws -> [Flashcard]
    func add(_ card: Flashcard) throws
    func update(_ card: Flashcard) throws
    func delete(id: UUID) throws
    func deleteCards(forModule moduleID: UUID) throws
}
