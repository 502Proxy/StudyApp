import Foundation
import Observation

/// An upcoming exam with everything the UI shows about it.
struct ExamOverview: Identifiable, Equatable {
    let exam: Exam
    let module: StudyModule
    let daysLeft: Int
    let plan: StudyPlan

    var id: UUID { exam.id }
    var countdown: String { ExamCountdown.text(days: daysLeft) }
    var shortCountdown: String { ExamCountdown.shortText(days: daysLeft) }
}

/// Input of the exam editor. Only manual exams are edited; detected ones follow the calendar.
struct ExamDraft: Identifiable {
    let id: UUID
    var moduleID: UUID
    var title: String
    var startDate: Date
    var location: String
    let isNew: Bool
}

/// Upcoming exams of all modules with their study plans; shared by „Heute“ and the module's exam section.
@MainActor
@Observable
final class ExamsViewModel {
    private(set) var upcoming: [ExamOverview] = []
    var editor: ExamDraft?
    var errorMessage: String?

    private let listExams: ListExamsUseCase
    private let saveExam: SaveExamUseCase
    private let removeExam: RemoveExamUseCase
    private let toggleItem: ToggleStudyPlanItemUseCase
    private let modules: any ModuleRepository
    private let slides: any SlideDocumentRepository
    private let flashcards: any FlashcardRepository
    private let generator: StudyPlanGenerator
    private let calendar: Calendar
    private let now: () -> Date

    init(
        exams: any ExamRepository,
        calendarRepository: any StudyCalendarRepository,
        modules: any ModuleRepository,
        slides: any SlideDocumentRepository,
        flashcards: any FlashcardRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { .now }
    ) {
        listExams = ListExamsUseCase(exams: exams, calendar: calendarRepository, modules: modules, clock: calendar)
        saveExam = SaveExamUseCase(repository: exams)
        removeExam = RemoveExamUseCase(repository: exams)
        toggleItem = ToggleStudyPlanItemUseCase(repository: exams)
        self.modules = modules
        self.slides = slides
        self.flashcards = flashcards
        generator = StudyPlanGenerator(calendar: calendar)
        self.calendar = calendar
        self.now = now
    }

    func load() {
        do {
            let current = now()
            let modulesByID = Dictionary(uniqueKeysWithValues: try modules.all().map { ($0.id, $0) })
            upcoming = try listExams(now: current).compactMap { exam in
                guard let module = modulesByID[exam.moduleID] else { return nil }
                let plan = generator.plan(
                    for: exam,
                    documents: try slides.documents(forModule: module.id),
                    hasFlashcards: !(try flashcards.cards(forModule: module.id)).isEmpty,
                    now: current
                )
                let days = ExamCountdown.days(until: exam.startDate, from: current, calendar: calendar)
                return ExamOverview(exam: exam, module: module, daysLeft: days, plan: plan)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exams(forModule moduleID: UUID) -> [ExamOverview] {
        upcoming.filter { $0.module.id == moduleID }
    }

    func toggle(_ item: StudyPlanItem, of exam: Exam) {
        perform { _ = try toggleItem(item.id, of: exam) }
    }

    /// Removes a manual exam or hides a detected one.
    func remove(_ exam: Exam) {
        perform { try removeExam(exam) }
    }

    // MARK: Editor

    func startNewExam(for module: StudyModule) {
        let inTwoWeeks = calendar.date(byAdding: .day, value: 14, to: calendar.startOfDay(for: now())) ?? now()
        editor = ExamDraft(
            id: UUID(),
            moduleID: module.id,
            title: "Klausur \(module.name)",
            startDate: calendar.date(bySettingHour: 10, minute: 0, second: 0, of: inTwoWeeks) ?? inTwoWeeks,
            location: "",
            isNew: true
        )
    }

    func edit(_ exam: Exam) {
        guard exam.isManual else { return }
        editor = ExamDraft(
            id: exam.id, moduleID: exam.moduleID, title: exam.title,
            startDate: exam.startDate, location: exam.location, isNew: false
        )
    }

    /// Returns `false` and keeps the editor open when the input is invalid.
    @discardableResult
    func save(_ draft: ExamDraft) -> Bool {
        let existing = upcoming.first { $0.exam.id == draft.id }?.exam
        let exam = Exam(
            id: draft.id,
            moduleID: draft.moduleID,
            title: draft.title,
            startDate: draft.startDate,
            location: draft.location,
            calendarEventKey: nil,
            completedPlanItems: existing?.completedPlanItems ?? []
        )
        do {
            try saveExam(exam)
            editor = nil
            load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
