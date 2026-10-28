import Foundation

/// Reads Anki text exports and packages, chosen by file extension.
struct AnkiFileReader: FlashcardFileReading {
    static let textExtensions: Set<String> = ["txt", "tsv", "csv"]
    static let packageExtension = "apkg"

    func cards(from url: URL) throws -> [ExchangedFlashcard] {
        let fileExtension = url.pathExtension.lowercased()
        let cards: [ExchangedFlashcard]
        if fileExtension == Self.packageExtension {
            cards = try AnkiPackageReader().cards(from: url)
        } else if Self.textExtensions.contains(fileExtension) {
            cards = AnkiTextFormat.decode(try String(contentsOf: url, encoding: .utf8))
        } else {
            throw FlashcardExchangeError.unsupportedFile
        }
        guard !cards.isEmpty else { throw FlashcardExchangeError.noCards }
        return cards
    }
}

/// Writes cards as an Anki text file („Notizen als Klartext“ import in Anki).
struct AnkiTextFileWriter: FlashcardFileWriting {
    func write(_ cards: [ExchangedFlashcard], to url: URL) throws {
        try AnkiTextFormat.encode(cards).write(to: url, atomically: true, encoding: .utf8)
    }
}
