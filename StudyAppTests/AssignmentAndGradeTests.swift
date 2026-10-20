import Foundation
import Testing
@testable import StudyApp

@MainActor
final class FakeAssignmentRepository: AssignmentRepository {
    var storage: [Assignment] = []

    func all() throws -> [Assignment] { storage }
    func add(_ assignment: Assignment) throws { storage.append(assignment) }

    func update(_ assignment: Assignment) throws {
        guard let index = storage.firstIndex(where: { $0.id == assignment.id }) else { throw AssignmentError.notFound }
        storage[index] = assignment
    }

    func delete(id: UUID) throws {
        guard storage.contains(where: { $0.id == id }) else { throw AssignmentError.notFound }
        storage.removeAll { $0.id == id }
    }

    func deleteAssignments(forModule moduleID: UUID) throws {
        storage.removeAll { $0.moduleID == moduleID }
    }
}

@MainActor
struct AssignmentTests {
    private let module = UUID()
    private let repository = FakeAssignmentRepository()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    @Test func saveTrimsAndRequiresATitle() throws {
        let save = SaveAssignmentUseCase(repository: repository)
        #expect(throws: AssignmentError.emptyTitle) {
            try save(moduleID: module, title: "  ", details: "", dueDate: date(23))
        }
        let created = try save(moduleID: module, title: "  Übungsblatt 3 ", details: " Aufgabe 2b ", dueDate: date(23))
        #expect(created.title == "Übungsblatt 3")
        #expect(created.details == "Aufgabe 2b")

        let updated = try save(id: created.id, moduleID: module, title: "Blatt 3", details: "", dueDate: date(24))
        #expect(updated.id == created.id)
        #expect(repository.storage.map(\.title) == ["Blatt 3"])
        #expect(repository.storage.first?.dueDate == date(24))
    }

    @Test func completionKeepsTheFirstCompletionDate() throws {
        let assignment = Assignment(moduleID: module, title: "A", dueDate: date(23))
        try repository.add(assignment)
        let complete = SetAssignmentCompletionUseCase(repository: repository, now: { date(22) })

        let done = try complete(assignment, isCompleted: true)
        #expect(done.completedAt == date(22))
        let again = try complete(done, isCompleted: true)
        #expect(again.completedAt == date(22))
        let reopened = try complete(again, isCompleted: false)
        #expect(!reopened.isCompleted)
    }

    @Test func openAssignmentsComeFirstByDueDate() {
        let late = Assignment(moduleID: module, title: "Spät", dueDate: date(30))
        let soon = Assignment(moduleID: module, title: "Bald", dueDate: date(21))
        let done = Assignment(moduleID: module, title: "Fertig", dueDate: date(19), completedAt: date(18))
        let sorted = [late, done, soon].sorted(by: Assignment.displayOrder)
        #expect(sorted.map(\.title) == ["Bald", "Spät", "Fertig"])
    }

    @Test func urgencyReflectsTheDueDate() {
        let now = date(20, 10)
        func urgency(_ due: Date, done: Bool = false) -> AssignmentUrgency {
            Assignment(moduleID: module, title: "x", dueDate: due, completedAt: done ? now : nil)
                .urgency(at: now, calendar: calendar)
        }
        #expect(urgency(date(20, 9)) == .overdue)
        #expect(urgency(date(20, 23)) == .today)
        #expect(urgency(date(22)) == .soon)
        #expect(urgency(date(30)) == .later)
        #expect(urgency(date(19), done: true) == .done)
    }

    @Test func dueTextIsReadable() {
        let now = date(20, 10)
        func text(_ due: Date) -> String {
            AssignmentFormatting.dueText(for: Assignment(moduleID: module, title: "x", dueDate: due), at: now, calendar: calendar)
        }
        #expect(text(date(20, 12)) == "heute, 12:00")
        #expect(text(date(21, 23, minute: 59)) == "morgen, 23:59")
        #expect(text(date(23)).hasPrefix("in 3 Tagen"))
        #expect(text(date(19)) == "seit gestern überfällig")
        #expect(text(date(15)) == "seit 5 Tagen überfällig")
    }

    @Test func viewModelListsUpcomingAndPerModule() throws {
        let other = UUID()
        try repository.add(Assignment(moduleID: module, title: "Überfällig", dueDate: date(18)))
        try repository.add(Assignment(moduleID: module, title: "Diese Woche", dueDate: date(24)))
        try repository.add(Assignment(moduleID: other, title: "Später", dueDate: date(31)))
        let viewModel = AssignmentsViewModel(repository: repository, calendar: calendar, now: { date(20, 10) })
        viewModel.load()

        #expect(viewModel.upcoming(days: 7).map(\.title) == ["Überfällig", "Diese Woche"])
        #expect(viewModel.overdueCount == 1)
        #expect(viewModel.openCount(forModule: module) == 2)
        #expect(viewModel.assignments(on: date(31)).map(\.title) == ["Später"])
    }

    @Test func draftWithoutModuleIsRejected() {
        let viewModel = AssignmentsViewModel(repository: repository, calendar: calendar, now: { date(20) })
        var draft = AssignmentDraft(moduleID: nil, now: date(20), calendar: calendar)
        draft.title = "Referat"
        #expect(!viewModel.save(draft))
        #expect(viewModel.errorMessage != nil)
        #expect(repository.storage.isEmpty)
        #expect(draft.dueDate == date(27))
    }

    @Test func deletingAModuleRemovesItsAssignments() throws {
        try repository.add(Assignment(moduleID: module, title: "A", dueDate: date(23)))
        let modules = FakeModuleRepository()
        let studyModule = StudyModule(id: module, name: "Analysis", code: "", color: .blue, createdAt: Date())
        try modules.add(studyModule)
        try DeleteModuleUseCase(
            repository: modules,
            slideRepository: FakeSlideDocumentRepository(),
            noteRepository: FakeNoteRepository(),
            flashcardRepository: FakeFlashcardRepository(),
            studySheetRepository: FakeStudySheetRepository(),
            fileStorage: FakeFileStorage(),
            assignmentRepository: repository
        )(studyModule)
        #expect(repository.storage.isEmpty)
    }
}

@MainActor
struct GradeTests {
    private func module(_ name: String, credits: Double?, grade: Double?) -> StudyModule {
        StudyModule(id: UUID(), name: name, code: "", color: .blue, createdAt: Date(), credits: credits, grade: grade)
    }

    @Test func averageIsWeightedByCreditsAndIgnoresFailedModules() throws {
        let summary = GradeSummary(modules: [
            module("Analysis", credits: 9, grade: 1.7),
            module("Programmierung", credits: 6, grade: 2.3),
            module("Physik", credits: 6, grade: 5.0),
            module("Seminar", credits: 3, grade: nil),
        ])
        let average = try #require(summary.weightedAverage)
        #expect(abs(average - 1.94) < 0.001)
        #expect(summary.earnedCredits == 15)
        #expect(summary.plannedCredits == 24)
        #expect(summary.gradedModuleCount == 3)
        #expect(summary.failedModuleCount == 1)
    }

    @Test func noGradesMeansNoAverage() {
        #expect(GradeSummary(modules: [module("A", credits: 6, grade: nil)]).weightedAverage == nil)
    }

    @Test func parsingAcceptsCommaAndEmptyInput() {
        #expect(GradeScale.parse("1,7") == .some(1.7))
        #expect(GradeScale.parse(" 2.3 ") == .some(2.3))
        #expect(GradeScale.parse("") == .some(nil))
        #expect(GradeScale.parse("gut") == nil)
        #expect(GradeScale.format(1.7) == "1,7")
        #expect(GradeScale.formatCredits(7.5) == "7,5")
        #expect(GradeScale.formatCredits(6) == "6")
    }

    @Test func updateValidatesAndRoundsTheGrade() throws {
        let repository = FakeModuleRepository()
        let original = module("Analysis", credits: nil, grade: nil)
        try repository.add(original)
        let update = UpdateModuleGradeUseCase(repository: repository)

        #expect(throws: GradeError.invalidGrade) { try update(original, credits: 6, grade: 0.7) }
        #expect(throws: GradeError.invalidCredits) { try update(original, credits: 90, grade: 2.0) }
        let saved = try update(original, credits: 6, grade: 1.66)
        #expect(saved.grade == 1.7)
        #expect(repository.storage.first?.credits == 6)
    }

    @Test func invalidGradeInTheEditorCreatesNoModule() {
        let repository = FakeModuleRepository()
        let viewModel = ModulesViewModel(
            repository: repository,
            slideRepository: FakeSlideDocumentRepository(),
            noteRepository: FakeNoteRepository(),
            flashcardRepository: FakeFlashcardRepository(),
            studySheetRepository: FakeStudySheetRepository(),
            fileStorage: FakeFileStorage(),
            settings: InMemoryStudyPreferences()
        )
        var draft = ModuleDraft()
        draft.name = "Analysis"
        draft.gradeText = "sehr gut"
        #expect(viewModel.save(draft) == nil)
        #expect(repository.storage.isEmpty)

        draft.gradeText = "1,3"
        draft.creditsText = "9"
        let saved = viewModel.save(draft)
        #expect(saved?.grade == 1.3)
        #expect(saved?.credits == 9)
    }
}

@MainActor
struct PrintableDocumentTests {
    @Test func studySheetDropsItsDuplicateTitleLine() {
        let sheet = StudySheet(moduleID: UUID(), title: "Lernzettel", content: "# Lernzettel\n\n## Themen\n- A", sourceNoteIDs: [])
        let document = PrintableDocument.studySheet(sheet, moduleName: "Analysis")
        #expect(document.title == "Lernzettel")
        #expect(document.sections.first?.content == "## Themen\n- A")
        #expect(document.fileName == "Lernzettel.pdf")
        #expect(document.subtitle.hasPrefix("Analysis · Lernzettel"))
    }

    @Test func emptyNotesAreNotPrinted() {
        let filled = LectureNote(id: UUID(), slideDocumentID: UUID(), title: "A", content: "Text", format: .markdown, pageNumber: 1, createdAt: Date(), updatedAt: Date())
        var empty = filled
        empty.content = " "
        let document = PrintableDocument.notes(title: "Notizen", subtitle: "", sections: [("Seite 1", filled), ("Seite 2", empty)])
        #expect(document.sections.map(\.heading) == ["Seite 1"])
    }
}
