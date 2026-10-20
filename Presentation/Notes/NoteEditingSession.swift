import Foundation
import Observation

/// Bearbeitungszustand einer einzelnen, bereits gespeicherten Notiz mit verzögertem Autosave.
/// Wird in der Notizübersicht genutzt, damit Notizen ohne geöffnete Folien bearbeitet werden können.
@MainActor
@Observable
final class NoteEditingSession {
    private(set) var note: LectureNote
    var title: String
    var content: String
    var format: NoteFormat
    private(set) var saveState: NotesViewModel.SaveState = .saved
    var errorMessage: String?

    @ObservationIgnored private let updateNote: UpdateNoteUseCase
    @ObservationIgnored private let autosaveDelay: Duration
    @ObservationIgnored private let onSaved: (LectureNote) -> Void
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    init(
        note: LectureNote,
        repository: any NoteRepository,
        autosaveDelay: Duration = .milliseconds(700),
        onSaved: @escaping (LectureNote) -> Void
    ) {
        self.note = note
        title = note.title
        content = note.content
        format = note.format
        updateNote = UpdateNoteUseCase(repository: repository)
        self.autosaveDelay = autosaveDelay
        self.onSaved = onSaved
    }

    var hasUnsavedChanges: Bool {
        title != note.title || content != note.content || format != note.format
    }

    /// Nach jeder Änderung aufrufen; startet den Autosave-Timer neu.
    func noteDidChange() {
        autosaveTask?.cancel()
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

    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard hasUnsavedChanges else {
            saveState = .saved
            return
        }
        do {
            note = try updateNote(note, title: title, content: content, format: format)
            // Ein leerer Titel wird nicht gespeichert; das Feld zeigt dann wieder den alten Titel.
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = note.title }
            saveState = .saved
            onSaved(note)
        } catch {
            errorMessage = error.localizedDescription
            saveState = .failed
        }
    }
}
