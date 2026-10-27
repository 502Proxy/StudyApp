import Foundation

// MARK: - Detection

/// Decides whether a calendar title names an exam. `nil` means "no opinion", so rules can be chained
/// (chain of responsibility over strategies): the first rule with an answer wins.
protocol ExamDetectionRule: Sendable {
    func isExam(title: String) -> Bool?
}

/// Preparation sessions, exam reviews and practice exams mention „Klausur“ but are not the exam itself.
struct ExcludedExamTopicsRule: ExamDetectionRule {
    static let excludedFragments = [
        "vorbereitung", "einsicht", "besprechung", "anmeldung", "fragestunde", "probeklausur", "repetitorium",
    ]

    func isExam(title: String) -> Bool? {
        let folded = CourseTitleAnalyzer.makeKey(title)
        return Self.excludedFragments.contains { folded.contains($0) } ? false : nil
    }
}

/// Uses the kind recognised by `CourseTitleAnalyzer` („Klausur Analysis I“, „Prüfung: Statistik“ …).
struct CourseKindExamRule: ExamDetectionRule {
    func isExam(title: String) -> Bool? {
        CourseTitleAnalyzer.analyze(title)?.kind == .exam ? true : nil
    }
}

struct ExamDetector: Sendable {
    var rules: [any ExamDetectionRule] = [ExcludedExamTopicsRule(), CourseKindExamRule()]

    func isExam(title: String) -> Bool {
        for rule in rules {
            if let answer = rule.isExam(title: title) { return answer }
        }
        return false
    }

    /// Exams among `events`, assigned to the linked module or the module whose name the title contains.
    func exams(in events: [StudyCalendarEvent], modules: [StudyModule]) -> [Exam] {
        let moduleByKey = Dictionary(
            modules.map { (DetectModuleCandidatesUseCase.moduleKey(for: $0), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        return events.compactMap { event in
            guard isExam(title: event.title) else { return nil }
            let key = CourseTitleAnalyzer.analyze(event.title)?.key
            guard let moduleID = event.moduleID ?? key.flatMap({ moduleByKey[$0] }) else { return nil }
            return Exam(
                id: .stable(from: "exam:\(event.externalID)"),
                moduleID: moduleID,
                title: event.title,
                startDate: event.startDate,
                location: event.location,
                calendarEventKey: event.externalID
            )
        }
    }
}

// MARK: - Listing and editing

/// Upcoming exams of active modules: detected ones merged with their stored state, plus manual ones.
@MainActor
struct ListExamsUseCase {
    let exams: any ExamRepository
    let calendar: any StudyCalendarRepository
    let modules: any ModuleRepository
    var detector = ExamDetector()
    var clock = Calendar.current

    func callAsFunction(now: Date) throws -> [Exam] {
        let activeModules = try modules.all().filter { !$0.isArchived }
        let activeIDs = Set(activeModules.map(\.id))
        let stored = try exams.all()
        let storedByKey = Dictionary(
            stored.compactMap { exam in exam.calendarEventKey.map { ($0, exam) } },
            uniquingKeysWith: { first, _ in first }
        )

        var result = stored.filter(\.isManual)
        for detected in detector.exams(in: try calendar.events(), modules: activeModules) {
            guard let key = detected.calendarEventKey, let state = storedByKey[key] else {
                result.append(detected)
                continue
            }
            guard !state.isHidden else { continue }
            // Date, room and title follow the calendar; the stored copy only contributes progress.
            var merged = detected
            merged.completedPlanItems = state.completedPlanItems
            result.append(merged)
        }
        let today = clock.startOfDay(for: now)
        return result
            .filter { activeIDs.contains($0.moduleID) && $0.startDate >= today }
            .sorted { $0.startDate < $1.startDate }
    }
}

@MainActor
struct SaveExamUseCase {
    let repository: any ExamRepository

    /// Creates or updates an exam entered by hand.
    @discardableResult
    func callAsFunction(_ exam: Exam) throws -> Exam {
        var cleaned = exam
        cleaned.title = exam.title.trimmed
        cleaned.location = exam.location.trimmed
        guard !cleaned.title.isEmpty else { throw ExamError.emptyTitle }
        try repository.save(cleaned)
        return cleaned
    }
}

/// Deletes a manual exam; a detected one is only hidden so the next calendar refresh does not bring it back.
@MainActor
struct RemoveExamUseCase {
    let repository: any ExamRepository

    func callAsFunction(_ exam: Exam) throws {
        if exam.isManual {
            try repository.delete(id: exam.id)
        } else {
            var hidden = exam
            hidden.isHidden = true
            try repository.save(hidden)
        }
    }
}

@MainActor
struct ToggleStudyPlanItemUseCase {
    let repository: any ExamRepository

    @discardableResult
    func callAsFunction(_ itemID: String, of exam: Exam) throws -> Exam {
        var updated = exam
        if updated.completedPlanItems.contains(itemID) {
            updated.completedPlanItems.remove(itemID)
        } else {
            updated.completedPlanItems.insert(itemID)
        }
        try repository.save(updated)
        return updated
    }
}

// MARK: - Study plan

/// Spreads the open learning items of a module over the days until its exam.
///
/// Every slide set is one item; on each day there is a flashcard review (if the module has cards);
/// the last day before the exam is kept for a final review when there are at least two days.
struct StudyPlanGenerator: Sendable {
    var calendar = Calendar.current

    func plan(for exam: Exam, documents: [SlideDocument], hasFlashcards: Bool, now: Date) -> StudyPlan {
        let days = learningDays(until: exam.startDate, from: now)
        let reservesFinalDay = days.count >= 2
        let slideDays = reservesFinalDay ? Array(days.dropLast()) : days

        let slideItems = documents
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            .map { StudyPlanItem(id: "slides.\($0.id.uuidString)", title: $0.title, kind: .slides(documentID: $0.id)) }
        let done = exam.completedPlanItems
        let openSlides = slideItems.filter { !done.contains($0.id) }

        var itemsByDay: [[StudyPlanItem]] = Array(repeating: [], count: days.count)
        for (index, item) in openSlides.enumerated() {
            // Even spread: item i goes to day ⌊i · days / items⌋.
            itemsByDay[index * slideDays.count / openSlides.count].append(item)
        }
        var completed = slideItems.filter { done.contains($0.id) }

        for (index, day) in days.enumerated() where hasFlashcards {
            let cards = StudyPlanItem(id: "cards.\(Self.dayKey(day, calendar: calendar))", title: "Fällige Karteikarten wiederholen", kind: .flashcards)
            if done.contains(cards.id) { completed.append(cards) } else { itemsByDay[index].append(cards) }
        }
        if reservesFinalDay {
            let review = StudyPlanItem(id: "review.final", title: "Gesamtwiederholung", kind: .finalReview)
            if done.contains(review.id) { completed.append(review) } else { itemsByDay[days.count - 1].append(review) }
        }

        let planDays = zip(days, itemsByDay)
            .map { StudyPlanDay(date: $0, items: $1) }
            .filter { !$0.items.isEmpty }
        return StudyPlan(days: planDays, completed: completed)
    }

    /// Today until the day before the exam; at least today, even if the exam is today.
    private func learningDays(until examDate: Date, from now: Date) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let examDay = calendar.startOfDay(for: examDate)
        var days: [Date] = []
        var day = today
        while day < examDay {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days.isEmpty ? [today] : days
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
