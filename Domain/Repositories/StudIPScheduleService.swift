import Foundation

/// A date of a Stud.IP course (lecture, exercise, exam …).
struct StudIPCourseDate: Hashable, Sendable {
    let id: String
    var title: String
    var details: String
    var location: String
    var start: Date
    var end: Date
    var isCancelled: Bool
}

/// Port for reading the dates of a course from Stud.IP.
@MainActor
protocol StudIPScheduleService {
    func courseDates(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPCourseDate]
}
