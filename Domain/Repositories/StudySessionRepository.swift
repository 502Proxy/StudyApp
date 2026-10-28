import Foundation

/// Stores the study timer's completed focus phases.
@MainActor
protocol StudySessionRepository {
    func all() throws -> [StudySession]
    func add(_ session: StudySession) throws
    func deleteSessions(forModule moduleID: UUID) throws
}
