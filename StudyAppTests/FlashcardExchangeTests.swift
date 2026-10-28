import Foundation
import Testing
@testable import StudyApp

@MainActor
struct FlashcardExchangeUseCaseTests {
    let repository = FakeFlashcardRepository()
    let module = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: .now)

    @Test func importSkipsDuplicatesAndEmptyCards() throws {
        try repository.add(Flashcard(moduleID: module.id, front: "Was ist ein Grenzwert?", back: "…"))
        let cards = [
            ExchangedFlashcard(front: "was ist  ein Grenzwert?", back: "doppelt"),
            ExchangedFlashcard(front: "Ableitung von x²", back: "2x"),
            ExchangedFlashcard(front: "Ableitung von x²", back: "nochmal"),
            ExchangedFlashcard(front: "  ", back: "ohne Frage"),
        ]

        let result = try ImportFlashcardsUseCase(repository: repository)(cards, intoModule: module.id)

        #expect(result == FlashcardImportResult(imported: 1, skippedDuplicates: 2, skippedEmpty: 1))
        #expect(try repository.cards(forModule: module.id).map(\.front) == ["Was ist ein Grenzwert?", "Ableitung von x²"])
    }

    @Test func emptyImportIsAnError() {
        #expect(throws: FlashcardExchangeError.noCards) {
            try ImportFlashcardsUseCase(repository: repository)([], intoModule: module.id)
        }
    }

    @Test func exportTagsCardsWithTheModule() throws {
        try repository.add(Flashcard(moduleID: module.id, front: "F", back: "B"))
        let cards = try ExportFlashcardsUseCase(repository: repository)(module: module)
        #expect(cards == [ExchangedFlashcard(front: "F", back: "B", tags: ["Analysis_I"])])
    }
}

@MainActor
struct AnkiTextFormatTests {
    @Test func roundTripKeepsTabsLineBreaksAndQuotes() {
        let cards = [
            ExchangedFlashcard(front: "Satz von \"Rolle\"", back: "Zeile 1\nZeile 2\tmit Tab", tags: ["Analysis_I"]),
            ExchangedFlashcard(front: "Einfach", back: "Antwort", tags: []),
        ]
        let text = AnkiTextFormat.encode(cards)
        #expect(text.hasPrefix("#separator:tab\n#html:false\n#tags column:3\n"))
        #expect(AnkiTextFormat.decode(text) == cards)
    }

    @Test func readsAnkiExportsWithHTMLAndOtherSeparators() {
        let export = "#separator:Semicolon\n#html:true\nVorderseite<br>zwei;\"Rückseite; mit &amp; Text\";extra\n"
        #expect(AnkiTextFormat.decode(export) == [
            ExchangedFlashcard(front: "Vorderseite\nzwei", back: "Rückseite; mit & Text"),
        ])
    }

    @Test func readsHeaderlessTabFilesAndSkipsSingleFields() {
        #expect(AnkiTextFormat.decode("Frage\tAntwort\nnur ein Feld\n\n") == [ExchangedFlashcard(front: "Frage", back: "Antwort")])
    }

    @Test func fieldTextDropsMediaAndResolvesCloze() {
        #expect(AnkiFieldText.plainText("Die {{c1::Ableitung::Begriff}} von x² ist 2x[sound:a.mp3]") == "Die Ableitung von x² ist 2x")
    }
}

@MainActor
final class FakeFlashcardFiles: FlashcardFileReading, FlashcardFileWriting {
    var cardsToRead: [ExchangedFlashcard] = []
    var readError: FlashcardExchangeError?
    private(set) var written: [ExchangedFlashcard] = []

    func cards(from url: URL) throws -> [ExchangedFlashcard] {
        if let readError { throw readError }
        return cardsToRead
    }

    func write(_ cards: [ExchangedFlashcard], to url: URL) throws { written = cards }
}

@MainActor
struct FlashcardExchangeViewModelTests {
    let repository = FakeFlashcardRepository()
    let files = FakeFlashcardFiles()
    let module = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: .now)
    let url = URL(filePath: "/tmp/deck.txt")

    private func makeViewModel() -> FlashcardExchangeViewModel {
        FlashcardExchangeViewModel(module: module, repository: repository, reader: files, writer: files)
    }

    @Test func importReportsTheResultAndReloads() {
        let viewModel = makeViewModel()
        var reloads = 0
        viewModel.onImported = { reloads += 1 }
        files.cardsToRead = [ExchangedFlashcard(front: "A", back: "1"), ExchangedFlashcard(front: "a", back: "2")]

        viewModel.importCards(from: url)

        #expect(viewModel.statusMessage == "1 Karte importiert · 1 schon vorhanden.")
        #expect(reloads == 1)
    }

    @Test func importErrorsAreShown() {
        let viewModel = makeViewModel()
        files.readError = .newPackageFormat
        viewModel.importCards(from: url)
        #expect(viewModel.errorMessage == FlashcardExchangeError.newPackageFormat.localizedDescription)
    }

    @Test func exportWritesTheModuleCards() throws {
        try repository.add(Flashcard(moduleID: module.id, front: "F", back: "B"))
        let viewModel = makeViewModel()
        viewModel.exportCards(to: url)
        #expect(files.written.map(\.front) == ["F"])
        #expect(viewModel.statusMessage == "1 Karte exportiert.")
        #expect(viewModel.suggestedExportName == "Analysis I – Karteikarten.txt")
    }
}
