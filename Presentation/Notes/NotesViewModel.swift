import Foundation
import Observation

/// Creates the view model for the notes of one slide document. Wired up in `AppContainer`.
typealias NotesViewModelFactory = @MainActor (SlideDocument) -> NotesViewModel

/// State and autosave logic for document-wide and per-page notes.
/// Autosave is debounced; changing the selected page flushes the current note first.
@MainActor
@Observable
final class NotesViewModel {
    enum SaveState: Equatable {
        case saved
        case pending
        case failed
    }

    let document: SlideDocument
    var content = ""
    var format: NoteFormat = .plainText
    /// `nil` selects the note for the whole document; positive values select a PDF page (1-based).
    private(set) var pageNumber: Int?
    private(set) var notesInDocument: [LectureNote] = []
    var searchQuery = ""
    private(set) var saveState: SaveState = .saved
    var errorMessage: String?

    private let getNote: GetNoteUseCase
    private let listNotes: ListNotesUseCase
    private let saveNote: SaveNoteUseCase
    private let autosaveDelay: Duration

    /// Last note known to be stored for the selected scope.
    @ObservationIgnored private var persisted: LectureNote?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    init(
        document: SlideDocument,
        repository: any NoteRepository,
        autosaveDelay: Duration = .milliseconds(800)
    ) {
        self.document = document
        self.autosaveDelay = autosaveDelay
        getNote = GetNoteUseCase(repository: repository)
        listNotes = ListNotesUseCase(repository: repository)
        saveNote = SaveNoteUseCase(repository: repository)
    }

    /// Whether the editor differs from the stored note in the selected scope.
    var hasUnsavedChanges: Bool {
        content != (persisted?.content ?? "") || format != (persisted?.format ?? .plainText)
    }

    /// Matches note content and page labels across this PDF's document-wide and page-specific notes.
    var searchResults: [LectureNote] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return notesForSearch
            .filter { note in
                note.title.localizedCaseInsensitiveContains(query)
                    || note.content.localizedCaseInsensitiveContains(query)
                    || (note.pageNumber.map { "Seite \($0)".localizedCaseInsensitiveContains(query) } ?? false)
            }
            .sorted(by: Self.noteOrder)
    }

    func load() {
        loadSelectedNote()
    }

    /// Adds the current editor buffer to stored notes, so search responds to unsaved edits too.
    private var notesForSearch: [LectureNote] {
        var result = notesInDocument
        if let current = currentNoteForExport(includingEmpty: true) {
            if let index = result.firstIndex(where: { $0.pageNumber == current.pageNumber }) {
                result[index] = current
            } else if !current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(current)
            }
        }
        return result.sorted(by: Self.noteOrder)
    }

    var hasExportableNotes: Bool {
        notesForExport().contains {
            !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Switches between the document-wide note (`nil`) and the note for a 1-based PDF page.
    /// Pending edits are saved before loading the other scope so a page change cannot discard text.
    func selectPageNumber(_ newPageNumber: Int?) {
        let normalized = newPageNumber.map { max(1, $0) }
        guard normalized != pageNumber else { return }

        saveNow()
        guard !hasUnsavedChanges else { return }
        pageNumber = normalized
        loadSelectedNote()
    }

    /// Opens a search result in the corresponding note scope.
    func selectNote(_ note: LectureNote) {
        selectPageNumber(note.pageNumber)
    }

    /// Call after every edit of `content` or `format`. Restarts the debounce timer.
    func noteDidChange() {
        autosaveTask?.cancel()
        autosaveTask = nil

        guard hasUnsavedChanges else {
            saveState = .saved
            return
        }
        saveState = .pending
        autosaveTask = Task { [weak self, delay = autosaveDelay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes pending edits immediately and cancels the debounce timer.
    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil

        guard hasUnsavedChanges else {
            saveState = .saved
            return
        }
        do {
            let saved = try saveNote(
                slideDocumentID: document.id,
                title: document.title,
                content: content,
                format: format,
                pageNumber: pageNumber
            )
            persisted = saved
            refreshDocumentNotes()
            saveState = .saved
        } catch {
            errorMessage = error.localizedDescription
            saveState = .failed
        }
    }

    /// Creates an export snapshot that includes the current unsaved editor contents.
    func currentNoteForExport(includingEmpty: Bool = false) -> LectureNote? {
        let hasContent = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard includingEmpty || hasContent else { return nil }
        let timestamp = Date()
        return LectureNote(
            id: persisted?.id ?? UUID(),
            slideDocumentID: document.id,
            title: document.title,
            content: content,
            format: format,
            pageNumber: pageNumber,
            createdAt: persisted?.createdAt ?? timestamp,
            updatedAt: timestamp
        )
    }

    /// All notes for the current PDF, overlaid with the current editor state.
    func notesForExport() -> [LectureNote] {
        var result = notesInDocument
        if let current = currentNoteForExport(includingEmpty: true) {
            if let index = result.firstIndex(where: { $0.pageNumber == current.pageNumber }) {
                result[index] = current
            } else if !current.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(current)
            }
        }
        return result.sorted(by: Self.noteOrder)
    }

    func exportAllNotesAsMarkdown() -> String {
        var sections = ["# Notizen: \(document.title)"]
        for note in notesForExport() where !note.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let heading = note.pageNumber.map { "Seite \($0)" } ?? "Gesamtdokument"
            let formatLabel = note.format.label
            sections.append("## \(heading)\n\n_Format: \(formatLabel)_\n\n\(note.content)")
        }
        return sections.joined(separator: "\n\n---\n\n") + "\n"
    }

    private func loadSelectedNote() {
        do {
            notesInDocument = try listNotes(slideDocumentID: document.id)
            persisted = try getNote(slideDocumentID: document.id, pageNumber: pageNumber)
            content = persisted?.content ?? ""
            format = persisted?.format ?? .plainText
            saveState = .saved
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshDocumentNotes() {
        do {
            notesInDocument = try listNotes(slideDocumentID: document.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func noteOrder(_ lhs: LectureNote, _ rhs: LectureNote) -> Bool {
        switch (lhs.pageNumber, rhs.pageNumber) {
        case (nil, nil): return lhs.updatedAt > rhs.updatedAt
        case (nil, _?): return true
        case (_?, nil): return false
        case let (left?, right?): return left == right ? lhs.updatedAt > rhs.updatedAt : left < right
        }
    }
}
