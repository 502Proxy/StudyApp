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
            mimeType: string(attributes["mime-type"]) ?? string(attributes["mime_type"])
        )
    }

    // MARK: Hilfen

    private static func object(_ data: Data) throws -> [String: Any] {
        // Eine HTML-Anmeldeseite statt JSON heißt meist: API aus oder Anmeldung umgeleitet.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StudIPError.invalidResponse
        }
        return object
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
