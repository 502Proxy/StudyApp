import Foundation

/// Zugang zu einer Stud.IP-Installation, z. B. `https://elearning.uni-oldenburg.de`.
struct StudIPAccount: Equatable, Sendable {
    var serverURL: URL
    var username: String
}

struct StudIPUser: Equatable, Sendable {
    /// Stud.IP-Nutzername, z. B. „tmueller13“.
    let username: String
    let displayName: String
}

/// Wie sich die App bei Stud.IP ausweist.
enum StudIPAuthorization: Equatable, Sendable {
    /// Nutzername und Passwort (HTTP Basic). Geht nicht bei Zwei-Faktor-Anmeldung.
    case password(String)
    /// Sitzung aus einer Anmeldung im Browserfenster, als Cookie-Header. Funktioniert auch mit 2FA,
    /// läuft aber irgendwann ab.
    case session(cookieHeader: String)
}

struct StudIPCredentials: Equatable, Sendable {
    let account: StudIPAccount
    let authorization: StudIPAuthorization

    init(account: StudIPAccount, authorization: StudIPAuthorization) {
        self.account = account
        self.authorization = authorization
    }

    init(account: StudIPAccount, password: String) {
        self.init(account: account, authorization: .password(password))
    }

    var usesSession: Bool {
        if case .session = authorization { return true }
        return false
    }
}

/// Wählt aus den Cookies einer Browser-Anmeldung die, die an den Stud.IP-Server gehen.
enum StudIPSessionCookies {
    /// - Returns: `nil`, solange es für den Server keine Cookies gibt.
    static func header(for cookies: [HTTPCookie], server: URL) -> String? {
        guard let host = server.host?.lowercased() else { return nil }
        let matching = cookies.filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let isExpired = cookie.expiresDate.map { $0 < Date() } ?? false
            return !isExpired && (host == domain || host.hasSuffix("." + domain))
        }
        guard !matching.isEmpty else { return nil }
        return matching
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }
}

/// Eine Veranstaltung, in die man in Stud.IP eingetragen ist.
struct StudIPCourse: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    /// Veranstaltungsnummer, z. B. „inf030“ oder „2.01.031“.
    var number: String
    /// Semesterbezeichnung, wie Stud.IP sie liefert, z. B. „WiSe 2025/26“.
    var semesterTitle: String?

    var semester: Semester? { semesterTitle.flatMap { Semester(title: $0) } }
}

/// Eine Datei im Dateibereich einer Veranstaltung.
struct StudIPFile: Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var size: Int?
    /// Änderungsstand (Stud.IP `chdate`). Ändert er sich, gibt es eine neue Fassung der Datei.
    var version: String
    var mimeType: String?
    /// Ordner innerhalb der Veranstaltung, z. B. „Übungen/Blatt 1“. Leer für den Hauptordner.
    var folderPath: String = ""
    var changedAt: Date?

    var isPDF: Bool {
        mimeType?.lowercased().contains("pdf") == true || name.lowercased().hasSuffix(".pdf")
    }
}
