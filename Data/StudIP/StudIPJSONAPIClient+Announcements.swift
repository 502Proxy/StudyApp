import Foundation

extension StudIPJSONAPIClient: StudIPAnnouncementService {
    func announcements(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPAnnouncement] {
        try await allResources("courses/\(courseID)/news", credentials)
            .compactMap(StudIPJSONAPIParser.announcement)
    }
}
