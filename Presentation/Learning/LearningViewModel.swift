import Foundation
import Observation

/// Coordinates the learning area. Persistence and scheduling stay in domain/data layers.
typealias LearningViewModelFactory = @MainActor (StudyModule) -> LearningViewModel

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
        let title = sourceDocumentTitle(for: note)
        guard let page = note.pageNumber else { return "\(title) · Gesamtdokument" }
        return "\(title) · Seite \(page)"
    }

    func load() {
        do {
            documents = try slideRepository.documents(forModule: module.id).sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            var loadedNotes: [LectureNote] = []
            for document in documents {
                loadedNotes.append(contentsOf: try noteRepository.notes(forSlideDocument: document.id))
            }
            notes = loadedNotes
                .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .sorted(by: Self.noteOrder)
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

    private static func noteOrder(_ lhs: LectureNote, _ rhs: LectureNote) -> Bool {
        if lhs.slideDocumentID != rhs.slideDocumentID {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        switch (lhs.pageNumber, rhs.pageNumber) {
        case (nil, nil): return lhs.updatedAt > rhs.updatedAt
        case (nil, _?): return true
        case (_?, nil): return false
        case let (left?, right?): return left == right ? lhs.updatedAt > rhs.updatedAt : left < right
        }
    }
}
