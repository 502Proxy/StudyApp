import Foundation

enum StudyCalendarError: LocalizedError, Equatable {
    case invalidSubscriptionURL
    case invalidCalendarData
    case sourceNotFound
    case emptyCalendar
    case feedUnavailable(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidSubscriptionURL: "Bitte gib eine gültige http-, https- oder webcal-Kalender-URL ein."
        case .invalidCalendarData: "Die Datei enthält keine gültigen iCalendar-Termine. Unterstützt werden .ics-Dateien."
        case .sourceNotFound: "Die Kalenderquelle wurde nicht gefunden."
        case .emptyCalendar: "Der Kalender enthält keine importierbaren Termine."
        case .feedUnavailable(let code): "Der Kalender-Server hat mit Status \(code) geantwortet."
        }
    }
}

/// Normalisiert eingegebene Abo-Adressen. `webcal://` ist nur ein Alias für `https://`.
enum CalendarFeedURL {
    static func normalized(_ input: String) throws -> URL {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased() else {
            throw StudyCalendarError.invalidSubscriptionURL
        }
        switch scheme {
        case "webcal", "webcals": components.scheme = "https"
        case "https", "http": components.scheme = scheme
        default: throw StudyCalendarError.invalidSubscriptionURL
        }
        guard let host = components.host, !host.isEmpty, let url = components.url else {
            throw StudyCalendarError.invalidSubscriptionURL
        }
        return url
    }
}

@MainActor
struct ListStudyCalendarUseCase {
    let repository: any StudyCalendarRepository
    func callAsFunction() throws -> (events: [StudyCalendarEvent], sources: [CalendarSource]) {
        (try repository.events().sorted { $0.startDate < $1.startDate }, try repository.sources())
    }
}

@MainActor
struct ImportCalendarEventsUseCase {
    let repository: any StudyCalendarRepository
    func callAsFunction(source: CalendarSource, events: [StudyCalendarEvent]) throws {
        guard !events.isEmpty else { throw StudyCalendarError.emptyCalendar }
        try repository.save(source: source)
        try repository.replaceEvents(forSource: source.id, with: events)
    }
}

/// Importiert eine lokale .ics-Datei. Erneutes Importieren derselben Datei aktualisiert die Quelle.
@MainActor
struct ImportCalendarFileUseCase {
    let repository: any StudyCalendarRepository
    let parser: any CalendarEventParsing

    /// - Returns: Anzahl der importierten Termine.
    func callAsFunction(data: Data, fileURL: URL, existing: CalendarSource?, now: Date = .now) throws -> Int {
        let source = CalendarSource(
            id: existing?.id ?? UUID(),
            name: fileURL.deletingPathExtension().lastPathComponent,
            url: fileURL.standardizedFileURL,
            lastSyncedAt: now,
            kind: .file
        )
        let events = try parser.parse(data, sourceID: source.id)
        try ImportCalendarEventsUseCase(repository: repository)(source: source, events: events)
        return events.count
    }
}

/// Lädt einen abonnierten Feed und gleicht dessen Termine mit dem gespeicherten Stand ab.
@MainActor
struct SyncCalendarSubscriptionUseCase {
    let repository: any StudyCalendarRepository
    let loader: any CalendarFeedLoader
    let parser: any CalendarEventParsing

    /// - Returns: Anzahl der Termine im Feed.
    func callAsFunction(url: URL, existing: CalendarSource?, now: Date = .now) async throws -> Int {
        let data = try await loader.load(from: url)
        let source = CalendarSource(
            id: existing?.id ?? UUID(),
            name: existing?.name ?? Self.suggestedName(for: url),
            url: url,
            lastSyncedAt: now,
            kind: .subscription
        )
        let events = try parser.parse(data, sourceID: source.id)
        try ImportCalendarEventsUseCase(repository: repository)(source: source, events: events)
        return events.count
    }

    static func suggestedName(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let isUsable = !name.isEmpty && name != "/"
        return isUsable ? name : (url.host ?? "Abonnierter Kalender")
    }
}

@MainActor
struct LinkCalendarEventToModuleUseCase {
    let repository: any StudyCalendarRepository
    func callAsFunction(eventID: UUID, moduleID: UUID?) throws {
        try repository.updateModuleLink(eventID: eventID, moduleID: moduleID)
    }

    func callAsFunction(eventIDs: [UUID], moduleID: UUID?) throws {
        try repository.updateModuleLinks(eventIDs: eventIDs, moduleID: moduleID)
    }
}

/// Entfernt eine Quelle samt aller importierten Termine.
@MainActor
struct RemoveCalendarSourceUseCase {
    let repository: any StudyCalendarRepository
    func callAsFunction(_ source: CalendarSource) throws {
        try repository.deleteSource(id: source.id)
    }
}
