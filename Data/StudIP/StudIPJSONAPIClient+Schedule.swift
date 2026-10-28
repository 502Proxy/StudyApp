import Foundation

extension StudIPJSONAPIClient: StudIPScheduleService {
    func courseDates(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPCourseDate] {
        try await allResources("courses/\(courseID)/events", credentials)
            .compactMap(StudIPJSONAPIParser.courseDate)
    }
}
