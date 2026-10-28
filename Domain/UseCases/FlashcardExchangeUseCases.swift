import Foundation

/// Adds imported cards to a module as new cards (due now). Cards whose front already exists in the
/// module are skipped, so importing the same deck twice does not duplicate it.
@MainActor
struct ImportFlashcardsUseCase {
    let repository: any FlashcardRepository
    var now: () -> Date = { .now }

    func callAsFunction(_ cards: [ExchangedFlashcard], intoModule moduleID: UUID) throws -> FlashcardImportResult {
        guard !cards.isEmpty else { throw FlashcardExchangeError.noCards }
        var known = Set(try repository.cards(forModule: moduleID).map { Self.key($0.front) })
        var result = FlashcardImportResult()
        let reference = now()
        for card in cards {
            let front = card.front.trimmed
            let back = card.back.trimmed
            guard !front.isEmpty, !back.isEmpty else {
                result.skippedEmpty += 1
                continue
            }
            guard known.insert(Self.key(front)).inserted else {
                result.skippedDuplicates += 1
                continue
            }
            try repository.add(Flashcard(
                moduleID: moduleID, front: front, back: back, dueAt: reference, createdAt: reference, updatedAt: reference
            ))
            result.imported += 1
        }
        return result
    }

    /// Fronts are compared without case and with collapsed whitespace.
    static func key(_ front: String) -> String {
        front.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The cards of a module for export, tagged with the module so they stay grouped in Anki.
@MainActor
struct ExportFlashcardsUseCase {
    let repository: any FlashcardRepository

    func callAsFunction(module: StudyModule) throws -> [ExchangedFlashcard] {
        let tag = Self.tag(for: module.name)
        return try repository.cards(forModule: module.id)
            .sorted { $0.createdAt < $1.createdAt }
            .map { ExchangedFlashcard(front: $0.front, back: $0.back, tags: [tag]) }
    }

    /// Anki tags cannot contain spaces: „Analysis I“ → „Analysis_I“.
    static func tag(for moduleName: String) -> String {
        moduleName.split(whereSeparator: \.isWhitespace).joined(separator: "_")
    }
}
