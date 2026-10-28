import Foundation

/// Collects what StudyApp offers to Spotlight: active modules, notes with content and study sheets.
@MainActor
struct BuildSearchIndexUseCase {
    let modules: any ModuleRepository
    let slides: any SlideDocumentRepository
    let notes: any NoteRepository
    let studySheets: any StudySheetRepository

    func callAsFunction() throws -> [SearchableItem] {
        var items: [SearchableItem] = []
        for module in try modules.all() where !module.isArchived {
            items.append(SearchableItem(
                target: .module(module.id),
                title: module.name,
                content: module.code,
                subtitle: "Modul",
                modifiedAt: nil
            ))
            // Module notes are stored under the module ID, lecture notes under their slide document.
            let documents = try slides.documents(forModule: module.id)
            let titles = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0.title) })
            for owner in [module.id] + documents.map(\.id) {
                for note in try notes.notes(forSlideDocument: owner) where note.hasContent {
                    let source = titles[owner].map { " · \($0)" } ?? ""
                    items.append(SearchableItem(
                        target: .note(moduleID: module.id, noteID: note.id),
                        title: note.title.isEmpty ? "Notiz" : note.title,
                        content: note.content,
                        subtitle: "Notiz · \(module.name)\(source)",
                        modifiedAt: note.updatedAt
                    ))
                }
            }
            for sheet in try studySheets.sheets(forModule: module.id) {
                items.append(SearchableItem(
                    target: .studySheet(moduleID: module.id, sheetID: sheet.id),
                    title: sheet.title,
                    content: sheet.content,
                    subtitle: "Lernzettel · \(module.name)",
                    modifiedAt: sheet.updatedAt
                ))
            }
        }
        return items
    }
}

/// Rebuilds the Spotlight index. Cheap enough to run on launch and after changes: a few hundred items.
@MainActor
struct ReindexSearchUseCase {
    let build: BuildSearchIndexUseCase
    let index: any SearchIndexing

    func callAsFunction() async throws {
        try await index.replaceAll(with: try build())
    }
}
