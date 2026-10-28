import Foundation
import Observation

/// Import and export of a module's flashcards (Anki). Kept apart from `LearningViewModel`, which
/// already covers notes, cards and study sheets.
@MainActor
@Observable
final class FlashcardExchangeViewModel {
    private(set) var statusMessage: String?
    var errorMessage: String?
    /// Called after cards were imported, so the card list reloads.
    @ObservationIgnored var onImported: (() -> Void)?

    let module: StudyModule
    private let importCards: ImportFlashcardsUseCase
    private let exportCards: ExportFlashcardsUseCase
    private let reader: any FlashcardFileReading
    private let writer: any FlashcardFileWriting

    init(
        module: StudyModule,
        repository: any FlashcardRepository,
        reader: any FlashcardFileReading,
        writer: any FlashcardFileWriting
    ) {
        self.module = module
        self.reader = reader
        self.writer = writer
        importCards = ImportFlashcardsUseCase(repository: repository)
        exportCards = ExportFlashcardsUseCase(repository: repository)
    }

    var suggestedExportName: String { "\(module.name) – Karteikarten.txt" }

    func importCards(from url: URL) {
        do {
            let result = try importCards(try reader.cards(from: url), intoModule: module.id)
            statusMessage = Self.summary(result)
            if result.imported > 0 { onImported?() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCards(to url: URL) {
        do {
            let cards = try exportCards(module: module)
            try writer.write(cards, to: url)
            statusMessage = cards.count == 1 ? "1 Karte exportiert." : "\(cards.count) Karten exportiert."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearStatus() {
        statusMessage = nil
    }

    static func summary(_ result: FlashcardImportResult) -> String {
        var parts = [result.imported == 1 ? "1 Karte importiert" : "\(result.imported) Karten importiert"]
        if result.skippedDuplicates > 0 {
            parts.append("\(result.skippedDuplicates) schon vorhanden")
        }
        if result.skippedEmpty > 0 {
            parts.append("\(result.skippedEmpty) unvollständig")
        }
        return parts.joined(separator: " · ") + "."
    }
}
