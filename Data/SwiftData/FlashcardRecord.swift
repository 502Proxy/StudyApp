import Foundation
import SwiftData

@Model
final class FlashcardRecord {
    @Attribute(.unique) var id: UUID
    var moduleID: UUID
    var sourceNoteID: UUID?
    var front: String
    var back: String
    var dueAt: Date
    var lastReviewedAt: Date?
    var repetitions: Int
    var intervalDays: Int
    var easeFactor: Double
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID,
        moduleID: UUID,
        sourceNoteID: UUID?,
        front: String,
        back: String,
        dueAt: Date,
        lastReviewedAt: Date?,
        repetitions: Int,
        intervalDays: Int,
        easeFactor: Double,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.moduleID = moduleID
        self.sourceNoteID = sourceNoteID
        self.front = front
        self.back = back
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
        self.repetitions = repetitions
        self.intervalDays = intervalDays
        self.easeFactor = easeFactor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension FlashcardRecord {
    convenience init(_ card: Flashcard) {
        self.init(
            id: card.id,
            moduleID: card.moduleID,
            sourceNoteID: card.sourceNoteID,
            front: card.front,
            back: card.back,
            dueAt: card.dueAt,
            lastReviewedAt: card.lastReviewedAt,
            repetitions: card.repetitions,
            intervalDays: card.intervalDays,
            easeFactor: card.easeFactor,
            createdAt: card.createdAt,
            updatedAt: card.updatedAt
        )
    }

    func toDomain() -> Flashcard {
        Flashcard(
            id: id,
            moduleID: moduleID,
            sourceNoteID: sourceNoteID,
            front: front,
            back: back,
            dueAt: dueAt,
            lastReviewedAt: lastReviewedAt,
            repetitions: repetitions,
            intervalDays: intervalDays,
            easeFactor: easeFactor,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func apply(_ card: Flashcard) {
        sourceNoteID = card.sourceNoteID
        front = card.front
        back = card.back
        dueAt = card.dueAt
        lastReviewedAt = card.lastReviewedAt
        repetitions = card.repetitions
        intervalDays = card.intervalDays
        easeFactor = card.easeFactor
        updatedAt = card.updatedAt
    }
}
