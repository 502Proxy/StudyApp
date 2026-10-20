import Foundation
import Testing
@testable import StudyApp

@MainActor
final class FakeFlashcardRepository: FlashcardRepository {
    var storage: [Flashcard] = []

    func cards(forModule moduleID: UUID) throws -> [Flashcard] {
        storage.filter { $0.moduleID == moduleID }
    }

    func add(_ card: Flashcard) throws { storage.append(card) }

    func update(_ card: Flashcard) throws {
        guard let index = storage.firstIndex(where: { $0.id == card.id }) else {
            throw FlashcardError.notFound
        }
        storage[index] = card
    }

    func delete(id: UUID) throws {
        guard storage.contains(where: { $0.id == id }) else { throw FlashcardError.notFound }
        storage.removeAll { $0.id == id }
    }

    func deleteCards(forModule moduleID: UUID) throws {
        storage.removeAll { $0.moduleID == moduleID }
    }
}

@MainActor
final class FakeStudySheetRepository: StudySheetRepository {
    var storage: [StudySheet] = []

    func sheets(forModule moduleID: UUID) throws -> [StudySheet] {
        storage.filter { $0.moduleID == moduleID }
    }

    func add(_ sheet: StudySheet) throws { storage.append(sheet) }

    func update(_ sheet: StudySheet) throws {
        guard let index = storage.firstIndex(where: { $0.id == sheet.id }) else {
            throw StudySheetError.notFound
        }
        storage[index] = sheet
    }

    func delete(id: UUID) throws {
        guard storage.contains(where: { $0.id == id }) else { throw StudySheetError.notFound }
        storage.removeAll { $0.id == id }
    }

    func deleteSheets(forModule moduleID: UUID) throws {
        storage.removeAll { $0.moduleID == moduleID }
    }
}

@MainActor
struct LearningUseCaseTests {
    @Test func saveFlashcardTrimsQuestionAndAnswer() throws {
        let repository = FakeFlashcardRepository()
        let moduleID = UUID()
        let save = SaveFlashcardUseCase(repository: repository)

        let card = try save(moduleID: moduleID, front: "  Was ist Clean Code? ", back: "  Lesbarer und wartbarer Code.  ")

        #expect(card.front == "Was ist Clean Code?")
        #expect(card.back == "Lesbarer und wartbarer Code.")
        #expect(try repository.cards(forModule: moduleID).count == 1)
    }

    @Test func saveFlashcardRejectsEmptyQuestion() {
        let repository = FakeFlashcardRepository()
        let save = SaveFlashcardUseCase(repository: repository)

        #expect(throws: FlashcardError.emptyQuestion) {
            try save(moduleID: UUID(), front: "  \n", back: "Antwort")
        }
    }

    @Test func failedRecallSchedulesQuickRetryAndResetsProgress() {
        let reviewedAt = Date(timeIntervalSince1970: 100_000)
        let card = Flashcard(
            moduleID: UUID(), front: "Frage", back: "Antwort",
            dueAt: reviewedAt, repetitions: 4, intervalDays: 20, easeFactor: 2.4,
            createdAt: reviewedAt, updatedAt: reviewedAt
        )

        let result = SpacedRepetitionScheduler().schedule(card, rating: .again, reviewedAt: reviewedAt)

        #expect(result.repetitions == 0)
        #expect(result.intervalDays == 0)
        #expect(result.dueAt == reviewedAt.addingTimeInterval(600))
        #expect(result.easeFactor < card.easeFactor)
    }

    @Test func goodRecallIncreasesIntervalsGradually() {
        let reviewedAt = Date(timeIntervalSince1970: 100_000)
        let first = Flashcard(moduleID: UUID(), front: "F", back: "A", dueAt: reviewedAt, createdAt: reviewedAt, updatedAt: reviewedAt)
        let scheduler = SpacedRepetitionScheduler()

        let firstReview = scheduler.schedule(first, rating: .good, reviewedAt: reviewedAt)
        let secondReview = scheduler.schedule(firstReview, rating: .good, reviewedAt: reviewedAt)
        let thirdReview = scheduler.schedule(secondReview, rating: .good, reviewedAt: reviewedAt)

        #expect(firstReview.intervalDays == 1)
        #expect(secondReview.intervalDays == 3)
        #expect(thirdReview.intervalDays >= 7)
    }

    @Test func createsStudySheetWithOriginalNotesOutlineAndSelfCheckQuestions() throws {
        let repository = FakeStudySheetRepository()
        let moduleID = UUID()
        let date = Date(timeIntervalSince1970: 100_000)
        let note = LectureNote(
            id: UUID(), slideDocumentID: UUID(), title: "Objektorientierung",
            content: "## Kapselung\n\nDaten und Verhalten werden gebündelt.",
            format: .markdown, pageNumber: 2, createdAt: date, updatedAt: date
        )

        let sheet = try CreateStudySheetUseCase(repository: repository, now: { date })(
            moduleID: moduleID, title: "OOP Lernzettel", notes: [note]
        )

        #expect(sheet.moduleID == moduleID)
        #expect(sheet.sourceNoteIDs == [note.id])
        #expect(sheet.content.contains("## Themenübersicht"))
        #expect(sheet.content.contains("Kapselung"))
        #expect(sheet.content.contains("Daten und Verhalten werden gebündelt."))
        #expect(sheet.content.contains("## Selbstkontrolle"))
        #expect(try repository.sheets(forModule: moduleID).count == 1)
    }

    @Test func studySheetRequiresAtLeastOneNote() {
        let useCase = CreateStudySheetUseCase(repository: FakeStudySheetRepository())

        #expect(throws: StudySheetError.noSourceNotes) {
            try useCase(moduleID: UUID(), title: "Lernzettel", notes: [])
        }
    }
}
