import Foundation
import Testing
@testable import StudyApp

@MainActor
struct QuickInfoTests {
    let modules = FakeModuleRepository()
    let calendar = InMemoryCalendarRepository()
    let flashcards = FakeFlashcardRepository()
    let now = Date(timeIntervalSince1970: 1_761_642_000)

    private func module(_ name: String, archived: Bool = false) throws -> StudyModule {
        let module = StudyModule(id: UUID(), name: name, code: "", color: .blue, createdAt: now, isArchived: archived)
        try modules.add(module)
        return module
    }

    private func event(_ module: StudyModule?, inMinutes minutes: Double, length: Double = 90) -> StudyCalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return StudyCalendarEvent(
            id: UUID(), externalID: UUID().uuidString, sourceID: UUID(), title: "VL", details: "", location: "HS 1",
            startDate: start, endDate: start.addingTimeInterval(length * 60), moduleID: module?.id
        )
    }

    @Test func nextLectureSkipsArchivedAndUnlinkedEvents() throws {
        let analysis = try module("Analysis I")
        let old = try module("Altes Modul", archived: true)
        calendar.storedEvents = [event(old, inMinutes: 10), event(nil, inMinutes: 20), event(analysis, inMinutes: 60)]

        let answer = try NextLectureUseCase(calendar: calendar, modules: modules)(now: now)

        #expect(answer?.module.name == "Analysis I")
    }

    @Test func nextLectureTextForRunningAndUpcomingLectures() throws {
        let analysis = try module("Analysis I")
        let running = NextLectureUseCase.Answer(event: event(analysis, inMinutes: -30), module: analysis)
        #expect(NextLectureUseCase.text(running, now: now) == "Analysis I läuft gerade in HS 1, noch 60 Minuten.")
        let later = NextLectureUseCase.Answer(event: event(analysis, inMinutes: 60), module: analysis)
        #expect(NextLectureUseCase.text(later, now: now).hasPrefix("Als Nächstes: Analysis I, heute um "))
        #expect(NextLectureUseCase.text(nil, now: now) == "Es steht keine Vorlesung an.")
    }

    @Test func dueCardsAreCountedPerActiveModule() throws {
        let analysis = try module("Analysis I")
        let algebra = try module("Lineare Algebra")
        try flashcards.add(Flashcard(moduleID: analysis.id, front: "a", back: "b", dueAt: now.addingTimeInterval(-60)))
        try flashcards.add(Flashcard(moduleID: algebra.id, front: "a", back: "b", dueAt: now.addingTimeInterval(-60)))
        try flashcards.add(Flashcard(moduleID: algebra.id, front: "c", back: "d", dueAt: now.addingTimeInterval(-60)))
        try flashcards.add(Flashcard(moduleID: algebra.id, front: "e", back: "f", dueAt: now.addingTimeInterval(3_600)))

        let counts = try DueCardsUseCase(modules: modules, flashcards: flashcards)(now: now)

        #expect(counts.map(\.due) == [2, 1])
        #expect(DueCardsUseCase.text(counts) == "3 Karten fällig: Lineare Algebra 2, Analysis I 1.")
        #expect(DueCardsUseCase.text([]) == "Keine Karteikarten fällig.")
    }
}
