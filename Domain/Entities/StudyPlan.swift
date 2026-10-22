import Foundation

/// One thing to do before an exam.
struct StudyPlanItem: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case slides(documentID: UUID)
        case flashcards
        case finalReview
    }

    /// Stable key, stored in `Exam.completedPlanItems`.
    let id: String
    let title: String
    let kind: Kind
}

struct StudyPlanDay: Identifiable, Hashable, Sendable {
    let date: Date
    let items: [StudyPlanItem]
    var id: Date { date }
}

/// What to learn on which day until an exam. Items that are already done are listed separately;
/// the open ones are spread over the remaining days, so the plan adapts when a day is missed.
struct StudyPlan: Equatable, Sendable {
    let days: [StudyPlanDay]
    let completed: [StudyPlanItem]

    var openItemCount: Int { days.reduce(0) { $0 + $1.items.count } }
    var totalCount: Int { openItemCount + completed.count }

    /// Share of finished items, 0…1.
    var progress: Double {
        totalCount == 0 ? 0 : Double(completed.count) / Double(totalCount)
    }
}
