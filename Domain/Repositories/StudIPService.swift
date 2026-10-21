import Foundation

enum StudIPError: LocalizedError, Equatable {
    case notConnected
    case invalidServerURL
    case unauthorized
    case notFound
    case server(statusCode: Int)
    case invalidResponse
    case offline

    var errorDescription: String? {
        switch self {
        case .notConnected: "Stud.IP ist noch nicht verbunden. Melde dich in den Einstellungen an."
        case .invalidServerURL: "Bitte gib die Adresse deines Stud.IP an, z. B. https://elearning.uni-oldenburg.de."
        case .unauthorized: "Stud.IP hat die Anmeldung abgelehnt. Prüfe Nutzername und Passwort."
        case .notFound: "Stud.IP hat die Anfrage nicht gefunden. Ist die JSON:API auf diesem Server freigeschaltet?"
        case .server(let code): "Der Stud.IP-Server hat mit Status \(code) geantwortet."
        case .invalidResponse: "Die Antwort von Stud.IP war unerwartet. Unterstützt der Server die JSON:API?"
        case .offline: "Stud.IP ist gerade nicht erreichbar. Bist du online?"
        }
    }
}

/// Port zur Stud.IP-JSON:API. Die Implementierung liegt in der Data-Schicht.
@MainActor
protocol StudIPService {
    /// Prüft die Zugangsdaten und liefert den Anzeigenamen der angemeldeten Person.
    func verify(_ credentials: StudIPCredentials) async throws -> String
    func courses(_ credentials: StudIPCredentials) async throws -> [StudIPCourse]
    func files(inCourse courseID: String, _ credentials: StudIPCredentials) async throws -> [StudIPFile]
    func download(_ file: StudIPFile, _ credentials: StudIPCredentials) async throws -> Data
}

/// Port für die gespeicherte Anmeldung. Das Passwort gehört in den Schlüsselbund, nicht in die Datenbank.
@MainActor
protocol StudIPAccountStore: AnyObject {
    func load() -> StudIPCredentials?
    func save(_ credentials: StudIPCredentials) throws
    func delete()
    /// Neue Folien beim Start und danach regelmäßig automatisch laden.
    var autoSyncSlides: Bool { get set }
    var lastSlideSync: Date? { get set }
}

/// Flüchtige Implementierung für Tests und Previews.
@MainActor
final class InMemoryStudIPAccountStore: StudIPAccountStore {
    var credentials: StudIPCredentials?
    var autoSyncSlides = true
    var lastSlideSync: Date?

    init(credentials: StudIPCredentials? = nil) {
        self.credentials = credentials
    }

    func load() -> StudIPCredentials? { credentials }
    func save(_ credentials: StudIPCredentials) throws { self.credentials = credentials }
    func delete() { credentials = nil }
}
