import Foundation

/// Stores exams entered by hand and the state of detected ones (hidden, study plan progress).
@MainActor
protocol ExamRepository {
    func all() throws -> [Exam]
    /// Inserts or replaces the exam with the same ID.
    func save(_ exam: Exam) throws
    func delete(id: UUID) throws
    func deleteExams(forModule moduleID: UUID) throws
}
