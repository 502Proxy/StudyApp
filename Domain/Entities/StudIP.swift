import Foundation

/// Zugang zu einer Stud.IP-Installation, z. B. `https://elearning.uni-oldenburg.de`.
struct StudIPAccount: Equatable, Sendable {
    var serverURL: URL
    var username: String
}

struct StudIPCredentials: Equatable, Sendable {
    let account: StudIPAccount
    let password: String
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
    var changedAt: Date? = nil

    var isPDF: Bool {
        mimeType?.lowercased().contains("pdf") == true || name.lowercased().hasSuffix(".pdf")
    }
}
