import Foundation
import SwiftData

/// Exams entered by hand and the stored state (hidden, progress) of detected ones.
@Model
final class ExamRecord {
    @Attribute(.unique) var id: UUID
    var moduleID: UUID
    var title: String
    var startDate: Date
    var location: String
    var calendarEventKey: String?
    var isHidden: Bool
    var completedPlanItems: [String]

    init(_ exam: Exam) {
        id = exam.id
        moduleID = exam.moduleID
        title = exam.title
        startDate = exam.startDate
        location = exam.location
        calendarEventKey = exam.calendarEventKey
        isHidden = exam.isHidden
        completedPlanItems = exam.completedPlanItems.sorted()
    }

    func apply(_ exam: Exam) {
        moduleID = exam.moduleID
        title = exam.title
        startDate = exam.startDate
        location = exam.location
        calendarEventKey = exam.calendarEventKey
        isHidden = exam.isHidden
        completedPlanItems = exam.completedPlanItems.sorted()
    }

    func toDomain() -> Exam {
        Exam(
            id: id, moduleID: moduleID, title: title, startDate: startDate, location: location,
            calendarEventKey: calendarEventKey, isHidden: isHidden, completedPlanItems: Set(completedPlanItems)
        )
    }
}
