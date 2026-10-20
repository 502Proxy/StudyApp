import Foundation

enum AssignmentError: Error, Equatable, LocalizedError {
    case emptyTitle
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyTitle: "Die Aufgabe braucht einen Titel."
        case .notFound: "Die Aufgabe wurde nicht gefunden."
        }
    }
}

@MainActor
protocol AssignmentRepository {
    func all() throws -> [Assignment]
    func add(_ assignment: Assignment) throws
    /// - Throws: `AssignmentError.notFound`, wenn es die Aufgabe nicht gibt.
    func update(_ assignment: Assignment) throws
    func delete(id: UUID) throws
    func deleteAssignments(forModule moduleID: UUID) throws
}
