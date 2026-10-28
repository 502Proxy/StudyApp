import Foundation
import Observation

/// Eine Notiz samt Herkunft, für „Zuletzt bearbeitet“ und die Schnellsuche.
struct NoteReference: Identifiable, Hashable {
    let note: LectureNote
    let module: StudyModule
    /// Titel des Foliensatzes, bei freien Modulnotizen der Notiztitel.
    let sourceTitle: String

    var id: UUID { note.id }
    var isModuleNote: Bool { note.isModuleNote(of: module.id) }

    var locationLabel: String {
        if isModuleNote { return module.name }
        let page = note.pageNumber.map { "Seite \($0)" } ?? "Gesamtdokument"
        return "\(sourceTitle) · \(page)"
    }

    var displayTitle: String {
        isModuleNote ? note.title : sourceTitle
    }

    var snippet: String { note.previewLine() ?? "" }
}

/// Daten für die Startseite „Heute“: Lernstand über alle Module und zuletzt bearbeitete Notizen.
/// Termine kommen aus `StudyCalendarViewModel`.
@MainActor
@Observable
final class TodayViewModel {
    private(set) var modules: [StudyModule] = []
    private(set) var dueCounts: [UUID: Int] = [:]
    private(set) var cardCounts: [UUID: Int] = [:]
    /// Alle Notizen mit Inhalt, zuletzt bearbeitete zuerst.
    private(set) var notes: [NoteReference] = []
    var errorMessage: String?

    private let moduleRepository: any ModuleRepository
    private let slideRepository: any SlideDocumentRepository
    private let noteRepository: any NoteRepository
    private let flashcardRepository: any FlashcardRepository
    private let now: () -> Date

    init(
        moduleRepository: any ModuleRepository,
        slideRepository: any SlideDocumentRepository,
        noteRepository: any NoteRepository,
        flashcardRepository: any FlashcardRepository,
        now: @escaping () -> Date = { .now }
    ) {
        self.moduleRepository = moduleRepository
        self.slideRepository = slideRepository
        self.noteRepository = noteRepository
        self.flashcardRepository = flashcardRepository
        self.now = now
    }

    var totalDue: Int { dueCounts.values.reduce(0, +) }
    var recentNotes: [NoteReference] { Array(notes.prefix(6)) }

    func module(withID id: UUID) -> StudyModule? {
        modules.first { $0.id == id }
    }

    func load() {
        do {
            modules = try ListModulesUseCase(repository: moduleRepository)()
            let reference = now()
            var due: [UUID: Int] = [:]
            var cards: [UUID: Int] = [:]
            var references: [NoteReference] = []

            for module in modules {
                let moduleCards = try flashcardRepository.cards(forModule: module.id)
                cards[module.id] = moduleCards.count
                due[module.id] = moduleCards.filter { $0.isDue(at: reference) }.count

                let slideDocuments = try slideRepository.documents(forModule: module.id)
                for document in slideDocuments {
                    for note in try noteRepository.notes(forSlideDocument: document.id) where note.hasContent {
                        references.append(NoteReference(note: note, module: module, sourceTitle: document.title))
                    }
                }
                for note in try noteRepository.notes(forSlideDocument: module.id) {
                    references.append(NoteReference(note: note, module: module, sourceTitle: note.title))
                }
            }

            dueCounts = due
            cardCounts = cards
            notes = references.sorted { $0.note.updatedAt > $1.note.updatedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
