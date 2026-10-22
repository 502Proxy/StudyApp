import Foundation

/// A question/answer card owned by a module and optionally linked to its source note.
struct Flashcard: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let moduleID: UUID
    var sourceNoteID: UUID?
    var front: String
    var back: String
    var dueAt: Date
    var lastReviewedAt: Date?
    var repetitions: Int
    var intervalDays: Int
    var easeFactor: Double
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        moduleID: UUID,
        sourceNoteID: UUID? = nil,
        front: String,
        back: String,
        dueAt: Date = Date(),
        lastReviewedAt: Date? = nil,
        repetitions: Int = 0,
        intervalDays: Int = 0,
        easeFactor: Double = 2.5,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.moduleID = moduleID
        self.sourceNoteID = sourceNoteID
        self.front = front
        self.back = back
        self.dueAt = dueAt
        self.lastReviewedAt = lastReviewedAt
        self.repetitions = max(0, repetitions)
        self.intervalDays = max(0, intervalDays)
        self.easeFactor = max(1.3, easeFactor)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func isDue(at date: Date = Date()) -> Bool {
        dueAt <= date
    }
}

enum FlashcardReviewRating: String, CaseIterable, Codable, Sendable, Identifiable {
    case again
    case hard
    case good
    case easy

    var id: Self { self }

    var label: String {
        switch self {
        case .again: "Nochmal"
        case .hard: "Schwer"
        case .good: "Gut"
        case .easy: "Einfach"
        }
    }

    var systemImage: String {
        switch self {
        case .again: "arrow.counterclockwise"
        case .hard: "tortoise"
        case .good: "checkmark"
        case .easy: "bolt"
        }
    }
}
