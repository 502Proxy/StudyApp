import Foundation

enum ModuleError: Error, Equatable, LocalizedError {
    case emptyName
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyName: "Der Modulname darf nicht leer sein."
        case .notFound: "Das Modul wurde nicht gefunden."
        }
    }
}

/// Zugriff auf gespeicherte Module. Die Implementierung liegt in der Data-Schicht.
/// MainActor, weil die SwiftData-Implementierung den Main-Context nutzt.
@MainActor
protocol ModuleRepository {
    func all() throws -> [StudyModule]
    func add(_ module: StudyModule) throws
    func update(_ module: StudyModule) throws
    func delete(id: UUID) throws
}
