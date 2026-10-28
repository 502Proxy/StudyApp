import Foundation

/// A flashcard in a neutral form for import and export (Anki text files and packages).
struct ExchangedFlashcard: Hashable, Sendable {
    var front: String
    var back: String
    var tags: [String] = []
}

/// What an import did.
struct FlashcardImportResult: Equatable, Sendable {
    var imported = 0
    /// Cards whose front already exists in the module (or twice in the file).
    var skippedDuplicates = 0
    /// Cards without front or back.
    var skippedEmpty = 0
}

enum FlashcardExchangeError: LocalizedError, Equatable {
    case unsupportedFile
    case unreadablePackage
    /// Anki 2.1.50+ packages use a compressed database StudyApp cannot read.
    case newPackageFormat
    case noCards

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "Unterstützt werden Anki-Textdateien (.txt, .tsv, .csv) und Anki-Pakete (.apkg)."
        case .unreadablePackage:
            "Das Anki-Paket konnte nicht gelesen werden."
        case .newPackageFormat:
            "Dieses Anki-Paket nutzt das neue Format. Exportiere es in Anki mit „Unterstützung älterer Anki-Versionen“ oder als Text („Notizen als Klartext“)."
        case .noCards:
            "Die Datei enthält keine Karteikarten."
        }
    }
}

/// Port for reading flashcards from a file chosen by the user.
@MainActor
protocol FlashcardFileReading {
    func cards(from url: URL) throws -> [ExchangedFlashcard]
}

/// Port for writing flashcards to a file.
@MainActor
protocol FlashcardFileWriting {
    func write(_ cards: [ExchangedFlashcard], to url: URL) throws
}
