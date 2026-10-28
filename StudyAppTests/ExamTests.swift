import Foundation
import Testing
@testable import StudyApp

@MainActor
final class InMemoryExamRepository: ExamRepository {
    var storage: [Exam] = []

    func all() throws -> [Exam] { storage }

    func save(_ exam: Exam) throws {
        storage.removeAll { $0.id == exam.id }
        storage.append(exam)
    }

    func delete(id: UUID) throws {
        guard storage.contains(where: { $0.id == id }) else { throw ExamError.notFound }
        storage.removeAll { $0.id == id }
    }

    func deleteExams(forModule moduleID: UUID) throws {
        storage.removeAll { $0.moduleID == moduleID }
    }
}

private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

private func day(_ day: Int, _ hour: Int = 10) -> Date {
    berlin.date(from: DateComponents(year: 2027, month: 2, day: day, hour: hour))!
}

// MARK: Detection

@MainActor
struct ExamDetectionTests {
    @Test(arguments: [
        ("Klausur Analysis I", true),
        ("Nachklausur Lineare Algebra", true),
        ("Prüfung: Statistik", true),
        ("Klausurvorbereitung Analysis I", false),
        ("Klausureinsicht Analysis I", false),
        ("Probeklausur Analysis I", false),
        ("Analysis I (Vorlesung)", false),
        ("Zahnarzt", false),
    ])
    func recognisesExamTitles(title: String, isExam: Bool) {
        #expect(ExamDetector().isExam(title: title) == isExam)
    }

    @Test func unlinkedExamIsAssignedToTheModuleNamedInTheTitle() {
        let analysis = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: Date())
        let event = StudyCalendarEvent(
            id: UUID(), externalID: "exam-1", sourceID: UUID(), title: "Klausur Analysis I", details: "", location: "Audimax",
            startDate: day(10), endDate: day(10, 12), moduleID: nil
        )

        let exams = ExamDetector().exams(in: [event], modules: [analysis])

        #expect(exams.count == 1)
        #expect(exams.first?.moduleID == analysis.id)
        #expect(exams.first?.location == "Audimax")
        #expect(exams.first?.id == .stable(from: "exam:exam-1"))
    }

    @Test func stableIDsAreDeterministicAndDistinct() {
        #expect(UUID.stable(from: "a") == UUID.stable(from: "a"))
        #expect(UUID.stable(from: "a") != UUID.stable(from: "b"))
        #expect(UUID.stable(from: "a").uuidString.dropFirst(14).first == "4")
    }

    @Test func countdownCountsCalendarDays() {
        #expect(ExamCountdown.days(until: day(10, 8), from: day(9, 23), calendar: berlin) == 1)
        #expect(ExamCountdown.text(days: 0) == "heute")
        #expect(ExamCountdown.text(days: 1) == "morgen")
        #expect(ExamCountdown.shortText(days: 1) == "morgen")
        #expect(ExamCountdown.shortText(days: 12) == "12 T.")
        #expect(ExamCountdown.text(days: 12) == "in 12 Tagen")
    }
}

// MARK: Listing and editing

@MainActor
struct ExamListTests {
    let exams = InMemoryExamRepository()
    let calendar = InMemoryCalendarRepository()
    let modules = FakeModuleRepository()
    let analysis = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: Date())

    private var list: ListExamsUseCase {
        ListExamsUseCase(exams: exams, calendar: calendar, modules: modules, clock: berlin)
    }

    private func addExamEvent(_ key: String, on date: Date, title: String = "Klausur Analysis I") throws {
        let source = UUID()
        try calendar.replaceEvents(forSource: source, with: [StudyCalendarEvent(
            id: UUID(), externalID: key, sourceID: source, title: title, details: "", location: "",
            startDate: date, endDate: date.addingTimeInterval(7_200), moduleID: analysis.id
        )])
    }

    @Test func detectedAndManualExamsAreMergedSortedAndPastOnesDropped() throws {
        try modules.add(analysis)
        try addExamEvent("late", on: day(20))
        try addExamEvent("past", on: day(1))
        try exams.save(Exam(id: UUID(), moduleID: analysis.id, title: "Mündliche Prüfung", startDate: day(12), location: "", calendarEventKey: nil))

        let result = try list(now: day(5))

        #expect(result.map(\.title) == ["Mündliche Prüfung", "Klausur Analysis I"])
    }

    @Test func storedProgressIsKeptAndHiddenExamsStayHidden() throws {
        try modules.add(analysis)
        try addExamEvent("kept", on: day(20))
        let detected = try #require(try list(now: day(5)).first)

        let ticked = try ToggleStudyPlanItemUseCase(repository: exams)("review.final", of: detected)
        #expect(try list(now: day(5)).first?.completedPlanItems == ["review.final"])
        #expect(ticked.completedPlanItems == ["review.final"])

        try RemoveExamUseCase(repository: exams)(try #require(try list(now: day(5)).first))
        #expect(try list(now: day(5)).isEmpty)
        #expect(exams.storage.count == 1)
    }

    @Test func examsOfArchivedModulesAreNotListed() throws {
        var archived = analysis
        archived.isArchived = true
        try modules.add(archived)
        try addExamEvent("archived", on: day(20))

        #expect(try list(now: day(5)).isEmpty)
    }

    @Test func manualExamsNeedATitleAndCanBeDeleted() throws {
        let save = SaveExamUseCase(repository: exams)
        #expect(throws: ExamError.emptyTitle) {
            try save(Exam(id: UUID(), moduleID: analysis.id, title: "  ", startDate: day(10), location: "", calendarEventKey: nil))
        }
        let exam = try save(Exam(id: UUID(), moduleID: analysis.id, title: " Klausur ", startDate: day(10), location: " A1 ", calendarEventKey: nil))
        #expect(exam.title == "Klausur")
        #expect(exam.location == "A1")

        try RemoveExamUseCase(repository: exams)(exam)
        #expect(exams.storage.isEmpty)
    }
}

// MARK: Study plan

@MainActor
struct StudyPlanTests {
    private let generator = StudyPlanGenerator(calendar: berlin)
    private let moduleID = UUID()

    private func documents(_ titles: [String]) -> [SlideDocument] {
        titles.map { SlideDocument(id: UUID(), moduleID: moduleID, title: $0, fileName: "\($0).pdf", pageCount: 10, importedAt: Date()) }
    }

    private func exam(on date: Date, completed: Set<String> = []) -> Exam {
        Exam(id: UUID(), moduleID: moduleID, title: "Klausur", startDate: date, location: "", calendarEventKey: nil, completedPlanItems: completed)
    }

    @Test func slidesAreSpreadEvenlyAndTheLastDayIsForReview() {
        let docs = documents(["VL 3", "VL 1", "VL 2"])
        let plan = generator.plan(for: exam(on: day(14)), documents: docs, hasFlashcards: true, now: day(10, 8))

        #expect(plan.days.map(\.date) == [day(10, 0), day(11, 0), day(12, 0), day(13, 0)])
        #expect(plan.days[0].items.map(\.title) == ["VL 1", "Fällige Karteikarten wiederholen"])
        #expect(plan.days[2].items.map(\.title) == ["VL 3", "Fällige Karteikarten wiederholen"])
        #expect(plan.days[3].items.map(\.title) == ["Fällige Karteikarten wiederholen", "Gesamtwiederholung"])
        #expect(plan.totalCount == 8)
        #expect(plan.progress == 0)
    }

    @Test func completedItemsMoveOutAndTheRestIsReplanned() {
        let docs = documents(["VL 1", "VL 2", "VL 3"])
        let done: Set = ["slides.\(docs[0].id.uuidString)", "slides.\(docs[1].id.uuidString)"]
        let plan = generator.plan(for: exam(on: day(14), completed: done), documents: docs, hasFlashcards: false, now: day(10, 8))

        #expect(plan.completed.map(\.title) == ["VL 1", "VL 2"])
        #expect(plan.days.first?.items.map(\.title) == ["VL 3"])
        #expect(plan.progress == 0.5)
    }

    @Test func examTodayPutsEverythingOnToday() {
        let plan = generator.plan(for: exam(on: day(10, 14)), documents: documents(["VL 1", "VL 2"]), hasFlashcards: false, now: day(10, 8))
        #expect(plan.days.count == 1)
        #expect(plan.days[0].items.map(\.title) == ["VL 1", "VL 2"])
    }

    @Test func moreDaysThanSlidesLeavesGaps() {
        let plan = generator.plan(for: exam(on: day(20)), documents: documents(["VL 1"]), hasFlashcards: false, now: day(10, 8))
        #expect(plan.days.map(\.items.count) == [1, 1])
        #expect(plan.days.last?.items.first?.kind == .finalReview)
    }
}

@MainActor
struct ExamsViewModelTests {
    @Test func overviewContainsCountdownAndPlan() throws {
        let exams = InMemoryExamRepository()
        let calendar = InMemoryCalendarRepository()
        let modules = FakeModuleRepository()
        let slides = FakeSlideDocumentRepository()
        let module = StudyModule(id: UUID(), name: "Analysis I", code: "", color: .blue, createdAt: Date())
        try modules.add(module)
        try slides.add(SlideDocument(id: UUID(), moduleID: module.id, title: "VL 1", fileName: "a.pdf", pageCount: 3, importedAt: Date()))
        let viewModel = ExamsViewModel(
            exams: exams, calendarRepository: calendar, modules: modules, slides: slides,
            flashcards: FakeFlashcardRepository(), calendar: berlin, now: { day(10, 8) }
        )

        viewModel.startNewExam(for: module)
        let draft = try #require(viewModel.editor)
        #expect(draft.title == "Klausur Analysis I")
        #expect(viewModel.save(draft))
        #expect(viewModel.editor == nil)

        let overview = try #require(viewModel.exams(forModule: module.id).first)
        #expect(overview.daysLeft == 14)
        #expect(overview.countdown == "in 14 Tagen")
        #expect(overview.plan.totalCount == 2)

        var empty = draft
        empty.title = ""
        #expect(!viewModel.save(empty))
        #expect(viewModel.errorMessage == ExamError.emptyTitle.errorDescription)
    }
}
