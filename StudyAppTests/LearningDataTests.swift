import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
struct LearningDataTests {
    @Test func flashcardRepositoryRoundTripsSchedulingState() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataFlashcardRepository(context: container.mainContext)
            let moduleID = UUID()
            let now = Date(timeIntervalSince1970: 10_000)
            let card = Flashcard(
                moduleID: moduleID,
                sourceNoteID: UUID(),
                front: "Was ist Abstraktion?",
                back: "Komplexität durch wesentliche Schnittstellen reduzieren.",
                dueAt: now.addingTimeInterval(86_400),
                lastReviewedAt: now,
                repetitions: 2,
                intervalDays: 3,
                easeFactor: 2.6,
                createdAt: now,
                updatedAt: now
            )

            try repository.add(card)
            let loaded = try #require(try repository.cards(forModule: moduleID).first)
            #expect(loaded.id == card.id)
            #expect(loaded.sourceNoteID == card.sourceNoteID)
            #expect(loaded.repetitions == 2)
            #expect(loaded.intervalDays == 3)
            #expect(loaded.easeFactor == 2.6)
            #expect(loaded.dueAt == card.dueAt)
        }
    }

    @Test func studySheetRepositoryRoundTripsSourceNoteIDs() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataStudySheetRepository(context: container.mainContext)
            let moduleID = UUID()
            let sourceIDs = [UUID(), UUID(), UUID()]
            let sheet = StudySheet(
                moduleID: moduleID,
                title: "Netzwerkgrundlagen",
                content: "# Netzwerkgrundlagen\n\n## Subnetting",
                sourceNoteIDs: sourceIDs
            )

            try repository.add(sheet)
            let loaded = try #require(try repository.sheets(forModule: moduleID).first)
            #expect(loaded.id == sheet.id)
            #expect(loaded.title == sheet.title)
            #expect(loaded.content == sheet.content)
            #expect(Set(loaded.sourceNoteIDs) == Set(sourceIDs))
        }
    }
}
