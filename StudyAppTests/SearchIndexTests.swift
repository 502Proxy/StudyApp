import Foundation
import Testing
@testable import StudyApp

struct SearchTargetTests {
    @Test func identifiersRoundTrip() {
        let targets: [SearchTarget] = [
            .module(UUID()),
            .note(moduleID: UUID(), noteID: UUID()),
            .studySheet(moduleID: UUID(), sheetID: UUID()),
        ]
        for target in targets {
            #expect(SearchTarget(identifier: target.identifier) == target)
        }
        #expect(SearchTarget(identifier: "note/kaputt") == nil)
        #expect(SearchTarget(identifier: "other/\(UUID().uuidString)") == nil)
    }
}

@MainActor
final class RecordingSearchIndex: SearchIndexing {
    private(set) var items: [SearchableItem] = []
    func replaceAll(with items: [SearchableItem]) async throws { self.items = items }
}

@MainActor
struct BuildSearchIndexTests {
    let modules = FakeModuleRepository()
    let slides = FakeSlideDocumentRepository()
    let notes = FakeNoteRepository()
    let sheets = FakeStudySheetRepository()
    let now = Date(timeIntervalSince1970: 1_760_000_000)

    private func note(_ owner: UUID, _ title: String, _ content: String) -> LectureNote {
        LectureNote(
            id: UUID(), slideDocumentID: owner, title: title, content: content,
            format: .markdown, pageNumber: nil, createdAt: now, updatedAt: now
        )
    }

    @Test func indexesActiveModulesNotesWithContentAndStudySheets() async throws {
        let analysis = StudyModule(id: UUID(), name: "Analysis I", code: "MAT101", color: .blue, createdAt: now)
        let archived = StudyModule(id: UUID(), name: "Alt", code: "", color: .blue, createdAt: now, isArchived: true)
        try modules.add(analysis)
        try modules.add(archived)
        let document = SlideDocument(id: UUID(), moduleID: analysis.id, title: "VL01", fileName: "a.pdf", pageCount: 3, importedAt: now)
        try slides.add(document)
        try notes.add(note(document.id, "Grenzwerte", "ε-δ-Definition"))
        try notes.add(note(analysis.id, "Fragen", "Warum konvergiert das?"))
        try notes.add(note(analysis.id, "Leer", "   "))
        try sheets.add(StudySheet(moduleID: analysis.id, title: "Klausur-Lernzettel", content: "Alles", sourceNoteIDs: []))

        let index = RecordingSearchIndex()
        let build = BuildSearchIndexUseCase(modules: modules, slides: slides, notes: notes, studySheets: sheets)
        try await ReindexSearchUseCase(build: build, index: index)()

        #expect(index.items.map(\.title).sorted() == ["Analysis I", "Fragen", "Grenzwerte", "Klausur-Lernzettel"])
        #expect(index.items.first { $0.title == "Grenzwerte" }?.subtitle == "Notiz · Analysis I · VL01")
        #expect(index.items.first { $0.title == "Fragen" }?.subtitle == "Notiz · Analysis I")
    }
}
