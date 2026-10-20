import Foundation

@MainActor
struct ListFlashcardsUseCase {
    let repository: any FlashcardRepository

    func callAsFunction(moduleID: UUID) throws -> [Flashcard] {
        try repository.cards(forModule: moduleID).sorted {
            if $0.dueAt != $1.dueAt { return $0.dueAt < $1.dueAt }
            return $0.createdAt < $1.createdAt
        }
    }
}

@MainActor
struct SaveFlashcardUseCase {
    let repository: any FlashcardRepository
    var now: () -> Date = { Date() }

    @discardableResult
    func callAsFunction(
        id: UUID? = nil,
        moduleID: UUID,
        sourceNoteID: UUID? = nil,
        front: String,
        back: String
    ) throws -> Flashcard {
        let question = front.trimmed
        let answer = back.trimmed
        guard !question.isEmpty else { throw FlashcardError.emptyQuestion }
        guard !answer.isEmpty else { throw FlashcardError.emptyAnswer }

        let timestamp = now()
        if let id {
            guard var existing = try repository.cards(forModule: moduleID).first(where: { $0.id == id }) else {
                throw FlashcardError.notFound
            }
            existing.sourceNoteID = sourceNoteID
            existing.front = question
            existing.back = answer
            existing.updatedAt = timestamp
            try repository.update(existing)
            return existing
        }

        let card = Flashcard(
            moduleID: moduleID,
            sourceNoteID: sourceNoteID,
            front: question,
            back: answer,
            dueAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try repository.add(card)
        return card
    }
}

@MainActor
struct DeleteFlashcardUseCase {
    let repository: any FlashcardRepository

    func callAsFunction(id: UUID) throws {
        try repository.delete(id: id)
    }
}

/// SM-2-inspired scheduler: ratings influence both the next interval and ease factor.
/// A missed card returns in ten minutes; successful recalls receive progressively longer intervals.
struct SpacedRepetitionScheduler: Sendable {
    var againDelay: TimeInterval = 10 * 60

    func schedule(
        _ card: Flashcard,
        rating: FlashcardReviewRating,
        reviewedAt: Date = Date()
    ) -> Flashcard {
        var updated = card
        updated.lastReviewedAt = reviewedAt
        updated.updatedAt = reviewedAt

        switch rating {
        case .again:
            updated.repetitions = 0
            updated.intervalDays = 0
            updated.easeFactor = max(1.3, card.easeFactor - 0.2)
            updated.dueAt = reviewedAt.addingTimeInterval(againDelay)

        case .hard:
            updated.intervalDays = switch card.repetitions {
            case 0: 1
            case 1: 2
            default: max(1, Int((Double(max(card.intervalDays, 1)) * 1.2).rounded()))
            }
            updated.repetitions = card.repetitions + 1
            updated.easeFactor = max(1.3, card.easeFactor - 0.15)
            updated.dueAt = reviewedAt.addingTimeInterval(TimeInterval(updated.intervalDays) * 86_400)

        case .good:
            updated.intervalDays = switch card.repetitions {
            case 0: 1
            case 1: 3
            default: max(1, Int((Double(max(card.intervalDays, 1)) * card.easeFactor).rounded()))
            }
            updated.repetitions = card.repetitions + 1
            // SM-2's ease adjustment for quality 4 leaves the factor unchanged.
            updated.dueAt = reviewedAt.addingTimeInterval(TimeInterval(updated.intervalDays) * 86_400)

        case .easy:
            updated.intervalDays = switch card.repetitions {
            case 0: 2
            case 1: 4
            default: max(1, Int((Double(max(card.intervalDays, 1)) * card.easeFactor * 1.3).rounded()))
            }
            updated.repetitions = card.repetitions + 1
            updated.easeFactor = max(1.3, card.easeFactor + 0.15)
            updated.dueAt = reviewedAt.addingTimeInterval(TimeInterval(updated.intervalDays) * 86_400)
        }

        return updated
    }
}

@MainActor
struct ReviewFlashcardUseCase {
    let repository: any FlashcardRepository
    var scheduler = SpacedRepetitionScheduler()
    var now: () -> Date = { Date() }

    @discardableResult
    func callAsFunction(id: UUID, moduleID: UUID, rating: FlashcardReviewRating) throws -> Flashcard {
        guard let card = try repository.cards(forModule: moduleID).first(where: { $0.id == id }) else {
            throw FlashcardError.notFound
        }
        let updated = scheduler.schedule(card, rating: rating, reviewedAt: now())
        try repository.update(updated)
        return updated
    }
}
