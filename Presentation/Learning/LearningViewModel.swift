import Foundation
import Observation

/// Coordinates the learning area. Persistence and scheduling stay in domain/data layers.
typealias LearningViewModelFactory = @MainActor (StudyModule) -> LearningViewModel

struct NoteSection: Identifiable {
    let id: UUID
    let title: String
    let systemImage: String
    let notes: [LectureNote]
}

struct FlashcardDraft {
    var id: UUID?
    var question: String
    var answer: String
    var sourceNoteID: UUID?
}

@MainActor
@Observable
final class LearningViewModel {
    let module: StudyModule

    private(set) var documents: [SlideDocument] = []
    private(set) var notes: [LectureNote] = []
    private(set) var flashcards: [Flashcard] = []
    private(set) var studySheets: [StudySheet] = []

    var noteSearchQuery = ""
    var cardSearchQuery = ""
    var selectedNoteID: UUID?
    var selectedNoteIDs: Set<UUID> = []
    var selectedStudySheetID: UUID?
    var errorMessage: String?

    private(set) var isReviewSessionActive = false
    private(set) var reviewQueue: [UUID] = []
    private(set) var answerIsRevealed = false

    private let slideRepository: any SlideDocumentRepository
    private let noteRepository: any NoteRepository
    private let createModuleNote: CreateModuleNoteUseCase
    private let deleteNoteUseCase: DeleteNoteUseCase
    private let listFlashcards: ListFlashcardsUseCase
    private let saveFlashcard: SaveFlashcardUseCase
    private let deleteFlashcard: DeleteFlashcardUseCase
    private let reviewFlashcard: ReviewFlashcardUseCase
    private let listStudySheets: ListStudySheetsUseCase
    private let createStudySheet: CreateStudySheetUseCase
    private let deleteStudySheet: DeleteStudySheetUseCase

    init(
        module: StudyModule,
        slideRepository: any SlideDocumentRepository,
        noteRepository: any NoteRepository,
        flashcardRepository: any FlashcardRepository,
        studySheetRepository: any StudySheetRepository
    ) {
        self.module = module
        self.slideRepository = slideRepository
        self.noteRepository = noteRepository
        createModuleNote = CreateModuleNoteUseCase(repository: noteRepository)
        deleteNoteUseCase = DeleteNoteUseCase(repository: noteRepository)
        listFlashcards = ListFlashcardsUseCase(repository: flashcardRepository)
        saveFlashcard = SaveFlashcardUseCase(repository: flashcardRepository)
        deleteFlashcard = DeleteFlashcardUseCase(repository: flashcardRepository)
        reviewFlashcard = ReviewFlashcardUseCase(repository: flashcardRepository)
        listStudySheets = ListStudySheetsUseCase(repository: studySheetRepository)
        createStudySheet = CreateStudySheetUseCase(repository: studySheetRepository)
        deleteStudySheet = DeleteStudySheetUseCase(repository: studySheetRepository)
    }

    var visibleNotes: [LectureNote] {
        let query = noteSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.content.localizedCaseInsensitiveContains(query)
                || sourceDocumentTitle(for: note).localizedCaseInsensitiveContains(query)
                || (note.pageNumber.map { "Seite \($0)".localizedCaseInsensitiveContains(query) } ?? false)
        }
    }

    var selectedNote: LectureNote? {
        guard let selectedNoteID else { return visibleNotes.first }
        return visibleNotes.first { $0.id == selectedNoteID } ?? visibleNotes.first
    }

    var selectedNotesForStudySheet: [LectureNote] {
        notes.filter { selectedNoteIDs.contains($0.id) }
    }

    var visibleFlashcards: [Flashcard] {
        let query = cardSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return flashcards }
        return flashcards.filter {
            $0.front.localizedCaseInsensitiveContains(query)
                || $0.back.localizedCaseInsensitiveContains(query)
        }
    }

    var dueFlashcards: [Flashcard] {
        flashcards.filter { $0.isDue() }.sorted { $0.dueAt < $1.dueAt }
    }

    var currentReviewCard: Flashcard? {
        guard isReviewSessionActive, let id = reviewQueue.first else { return nil }
        return flashcards.first { $0.id == id }
    }

    var reviewedTodayCount: Int {
        let calendar = Calendar.current
        return flashcards.filter { card in
            guard let lastReviewedAt = card.lastReviewedAt else { return false }
            return calendar.isDateInToday(lastReviewedAt)
        }.count
    }

    func sourceDocumentTitle(for note: LectureNote) -> String {
        documents.first(where: { $0.id == note.slideDocumentID })?.title ?? note.title
    }

    func sourceLabel(for note: LectureNote) -> String {
        if note.isModuleNote(of: module.id) { return "Notiz · \(note.title)" }
        let title = sourceDocumentTitle(for: note)
        guard let page = note.pageNumber else { return "\(title) · Gesamtdokument" }
        return "\(title) · Seite \(page)"
    }

    /// Foliensatz einer Notiz, `nil` für freie Modulnotizen.
    func document(for note: LectureNote) -> SlideDocument? {
        documents.first { $0.id == note.slideDocumentID }
    }

    func isModuleNote(_ note: LectureNote) -> Bool {
        note.isModuleNote(of: module.id)
    }

    /// Sichtbare Notizen, gruppiert: freie Notizen zuerst, danach je Foliensatz.
    var noteSections: [NoteSection] {
        let visible = visibleNotes
        var sections: [NoteSection] = []
        let moduleNotes = visible.filter { $0.isModuleNote(of: module.id) }
        if !moduleNotes.isEmpty {
            sections.append(NoteSection(id: module.id, title: "Vorlesungs- & Modulnotizen", systemImage: "square.and.pencil", notes: moduleNotes))
        }
        for document in documents {
            let notes = visible.filter { $0.slideDocumentID == document.id }
            if !notes.isEmpty {
                sections.append(NoteSection(id: document.id, title: document.title, systemImage: "doc.richtext", notes: notes))
            }
        }
        return sections
    }

    func load() {
        do {
            documents = try slideRepository.documents(forModule: module.id).sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            var loadedNotes: [LectureNote] = []
            for document in documents {
                // Leere Folien-Notizen entstehen beim Blättern und sind hier ohne Wert.
                loadedNotes.append(contentsOf: try noteRepository.notes(forSlideDocument: document.id).filter(\.hasContent))
            }
            loadedNotes.append(contentsOf: try noteRepository.notes(forSlideDocument: module.id))
            notes = loadedNotes.sorted(by: noteOrder)
            if let selectedNoteID, !notes.contains(where: { $0.id == selectedNoteID }) {
                self.selectedNoteID = nil
            }
            selectedNoteIDs.formIntersection(Set(notes.map(\.id)))
            if self.selectedNoteID == nil {
                self.selectedNoteID = notes.first?.id
            }
            flashcards = try listFlashcards(moduleID: module.id)
            studySheets = try listStudySheets(moduleID: module.id)
            if let selectedStudySheetID, !studySheets.contains(where: { $0.id == selectedStudySheetID }) {
                self.selectedStudySheetID = nil
            }
            if self.selectedStudySheetID == nil {
                self.selectedStudySheetID = studySheets.first?.id
            }
            reviewQueue = reviewQueue.filter { id in flashcards.contains(where: { $0.id == id }) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Notizen bearbeiten

    /// Legt eine freie Notiz an (ohne Folien) und wählt sie aus.
    @discardableResult
    func addModuleNote(title: String = "Neue Notiz", content: String = "") -> LectureNote? {
        do {
            let note = try createModuleNote(moduleID: module.id, title: title, content: content)
            notes.append(note)
            notes = notes.sorted(by: noteOrder)
            noteSearchQuery = ""
            selectedNoteID = note.id
            return note
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Öffnet die Notiz zu einem Vorlesungstermin; existiert sie noch nicht, wird sie angelegt.
    @discardableResult
    func openLectureNote(start: Date, eventTitle: String) -> LectureNote? {
        let kind = CourseTitleAnalyzer.analyze(eventTitle)?.kind ?? .lecture
        let label = kind == .other ? "Vorlesung" : kind.label
        let title = "\(label) vom \(start.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()))"
        if let existing = notes.first(where: { isModuleNote($0) && $0.title == title }) {
            noteSearchQuery = ""
            selectedNoteID = existing.id
            return existing
        }
        return addModuleNote(title: title, content: "# \(title)\n\n")
    }

    func deleteNote(_ note: LectureNote) {
        do {
            try deleteNoteUseCase(id: note.id)
            notes.removeAll { $0.id == note.id }
            selectedNoteIDs.remove(note.id)
            if selectedNoteID == note.id { selectedNoteID = visibleNotes.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func makeEditingSession(for note: LectureNote) -> NoteEditingSession {
        NoteEditingSession(note: note, repository: noteRepository) { [weak self] saved in
            self?.noteDidSave(saved)
        }
    }

    private func noteDidSave(_ note: LectureNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.append(note)
            notes = notes.sorted(by: noteOrder)
        }
    }

    func setNoteSelected(_ id: UUID, isSelected: Bool) {
        if isSelected { selectedNoteIDs.insert(id) } else { selectedNoteIDs.remove(id) }
    }

    func selectAllVisibleNotes() {
        selectedNoteIDs.formUnion(visibleNotes.map(\.id))
    }

    func clearNoteSelection() {
        selectedNoteIDs.removeAll()
    }

    /// Uses the note as a starting point but leaves the question and answer fully editable.
    func draftForNote(_ note: LectureNote) -> FlashcardDraft {
        let source = sourceLabel(for: note)
        return FlashcardDraft(
            id: nil,
            question: "Was sind die wichtigsten Inhalte aus \(source)?",
            answer: note.content,
            sourceNoteID: note.id
        )
    }

    @discardableResult
    func saveCard(_ draft: FlashcardDraft) -> Bool {
        do {
            try saveFlashcard(
                id: draft.id,
                moduleID: module.id,
                sourceNoteID: draft.sourceNoteID,
                front: draft.question,
                back: draft.answer
            )
            flashcards = try listFlashcards(moduleID: module.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteCard(_ card: Flashcard) {
        do {
            try deleteFlashcard(id: card.id)
            flashcards.removeAll { $0.id == card.id }
            reviewQueue.removeAll { $0 == card.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startReviewSession() {
        reviewQueue = dueFlashcards.map(\.id)
        answerIsRevealed = false
        isReviewSessionActive = true
    }

    func revealAnswer() {
        guard currentReviewCard != nil else { return }
        answerIsRevealed = true
    }

    func rateCurrentCard(_ rating: FlashcardReviewRating) {
        guard let card = currentReviewCard else { return }
        do {
            try reviewFlashcard(id: card.id, moduleID: module.id, rating: rating)
            flashcards = try listFlashcards(moduleID: module.id)
            if !reviewQueue.isEmpty { reviewQueue.removeFirst() }
            answerIsRevealed = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endReviewSession() {
        isReviewSessionActive = false
        reviewQueue.removeAll()
        answerIsRevealed = false
    }

    @discardableResult
    func makeStudySheet(title: String) -> Bool {
        do {
            let sheet = try createStudySheet(
                moduleID: module.id,
                title: title,
                notes: selectedNotesForStudySheet
            )
            studySheets.insert(sheet, at: 0)
            selectedStudySheetID = sheet.id
            clearNoteSelection()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSheet(_ sheet: StudySheet) {
        do {
            try deleteStudySheet(id: sheet.id)
            studySheets.removeAll { $0.id == sheet.id }
            if selectedStudySheetID == sheet.id {
                selectedStudySheetID = studySheets.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Freie Notizen zuerst (neueste oben), dann nach Foliensatz und Seite.
    /// Sortiert nach `createdAt`, damit die Liste beim Tippen nicht springt.
    private func noteOrder(_ lhs: LectureNote, _ rhs: LectureNote) -> Bool {
        let lhsIsModuleNote = lhs.isModuleNote(of: module.id)
        let rhsIsModuleNote = rhs.isModuleNote(of: module.id)
        if lhsIsModuleNote != rhsIsModuleNote { return lhsIsModuleNote }
        if lhsIsModuleNote { return lhs.createdAt > rhs.createdAt }
        if lhs.slideDocumentID != rhs.slideDocumentID {
            return sourceDocumentTitle(for: lhs).localizedStandardCompare(sourceDocumentTitle(for: rhs)) == .orderedAscending
        }
        switch (lhs.pageNumber, rhs.pageNumber) {
        case (nil, nil): return lhs.updatedAt > rhs.updatedAt
        case (nil, _?): return true
        case (_?, nil): return false
        case let (left?, right?): return left == right ? lhs.updatedAt > rhs.updatedAt : left < right
        }
    }
}
