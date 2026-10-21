import Foundation

/// Liest Antworten der Stud.IP-JSON:API (https://jsonapi.org). Bewusst nachsichtig:
/// Stud.IP-Versionen unterscheiden sich in einzelnen Attributen, fehlende Werte sind kein Fehler.
enum StudIPJSONAPIParser {
    typealias Resource = [String: Any]

    struct Page {
        let resources: [Resource]
        /// Link zur nächsten Seite, absolut oder relativ zum Server.
        let next: String?
    }

    static func page(_ data: Data) throws -> Page {
        let document = try object(data)
        let resources: [Resource]
        if let list = document["data"] as? [Resource] {
            resources = list
        } else if let single = document["data"] as? Resource {
            resources = [single]
        } else {
            throw StudIPError.invalidResponse
        }
        let links = document["links"] as? [String: Any]
        let next = (links?["next"] as? String) ?? ((links?["next"] as? [String: Any])?["href"] as? String)
        return Page(resources: resources, next: next)
    }

    /// ID und Anzeigename aus `users/me`.
    static func currentUser(_ data: Data) throws -> (id: String, name: String) {
        guard let user = try page(data).resources.first, let id = identifier(user) else {
            throw StudIPError.invalidResponse
        }
        let attributes = user["attributes"] as? [String: Any] ?? [:]
        let name = string(attributes["formatted-name"]) ?? string(attributes["username"]) ?? id
        return (id, name)
    }

    /// Semester-ID → Titel, z. B. „WiSe 2025/26“.
    static func semesterTitles(_ resources: [Resource]) -> [String: String] {
        var titles: [String: String] = [:]
        for resource in resources {
            guard let id = identifier(resource),
                  let title = string((resource["attributes"] as? [String: Any])?["title"]) else { continue }
            titles[id] = title
        }
        return titles
    }

    static func course(_ resource: Resource, semesterTitles: [String: String]) -> StudIPCourse? {
        guard let id = identifier(resource) else { return nil }
        let attributes = resource["attributes"] as? [String: Any] ?? [:]
        guard let title = string(attributes["title"]) else { return nil }
        let relationships = resource["relationships"] as? [String: Any] ?? [:]
        let semesterID = relatedID(relationships["start-semester"]) ?? relatedID(relationships["semester"])
        return StudIPCourse(
            id: id,
            title: title,
            number: string(attributes["course-number"]) ?? "",
            semesterTitle: semesterID.flatMap { semesterTitles[$0] }
        )
    }

    static func file(_ resource: Resource) -> StudIPFile? {
        guard let id = identifier(resource) else { return nil }
        let attributes = resource["attributes"] as? [String: Any] ?? [:]
        guard let name = string(attributes["name"]) else { return nil }
        let version = string(attributes["chdate"]) ?? string(attributes["mkdate"]) ?? ""
        return StudIPFile(
            id: id,
            name: name,
            size: (attributes["filesize"] as? NSNumber)?.intValue ?? string(attributes["filesize"]).flatMap { Int($0) },
            version: version,
            mimeType: string(attributes["mime-type"]) ?? string(attributes["mime_type"]),
            changedAt: date(attributes["chdate"]) ?? date(attributes["mkdate"])
        )
    }

    /// Ordner, in dem eine Datei liegt (Beziehung `parent`).
    static func parentFolderID(_ resource: Resource) -> String? {
        relatedID((resource["relationships"] as? [String: Any])?["parent"])
    }

    /// Ordner-ID → Pfad wie „Übungen/Blatt 1“. Der Hauptordner der Veranstaltung (ohne Elternordner) ist leer.
    static func folderPaths(_ resources: [Resource]) -> [String: String] {
        var folders: [String: (name: String, parent: String?)] = [:]
        for resource in resources {
            guard let id = identifier(resource) else { continue }
            let name = string((resource["attributes"] as? [String: Any])?["name"]) ?? ""
            folders[id] = (name, parentFolderID(resource))
        }
        var paths: [String: String] = [:]
        for id in folders.keys {
            var components: [String] = []
            var current: String? = id
            var visited: Set<String> = []
            // Bis zum Hauptordner hochlaufen; `visited` schützt vor kaputten Zyklen.
            while let folderID = current, let folder = folders[folderID], folder.parent != nil, visited.insert(folderID).inserted {
                components.insert(folder.name, at: 0)
                current = folder.parent
            }
            paths[id] = components.filter { !$0.isEmpty }.joined(separator: "/")
        }
        return paths
    }

    // MARK: Hilfen

    private static func object(_ data: Data) throws -> [String: Any] {
        // Eine HTML-Anmeldeseite statt JSON heißt meist: API aus oder Anmeldung umgeleitet.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StudIPError.invalidResponse
        }
        return object
    }

    /// Stud.IP liefert Zeitpunkte als ISO-8601-Text oder als Unix-Zeitstempel.
    private static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let text = value as? String else { return nil }
        if let seconds = Double(text) { return Date(timeIntervalSince1970: seconds) }
        return ISO8601DateFormatter().date(from: text)
    }

    private static func identifier(_ resource: Resource) -> String? {
        string(resource["id"])
    }

    private static func relatedID(_ relationship: Any?) -> String? {
        ((relationship as? [String: Any])?["data"] as? [String: Any]).flatMap { string($0["id"]) }
    }

    /// Strings bleiben, Zahlen (z. B. Unix-Zeitstempel) werden zu Text.
    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmed
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
