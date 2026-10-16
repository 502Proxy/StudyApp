import Foundation
import Observation

@MainActor
@Observable
final class StudyCalendarViewModel {
    private(set) var events: [StudyCalendarEvent] = []
    private(set) var sources: [CalendarSource] = []
    private(set) var modules: [StudyModule] = []
    var errorMessage: String?
    var statusMessage: String?
    var subscriptionURL = ""
    var selectedEvent: StudyCalendarEvent?

    private let repository: any StudyCalendarRepository
    private let moduleRepository: any ModuleRepository
    private let listCalendar: ListStudyCalendarUseCase
    private let importEvents: ImportCalendarEventsUseCase
    private let linkEvent: LinkCalendarEventToModuleUseCase

    init(repository: any StudyCalendarRepository, moduleRepository: any ModuleRepository) {
        self.repository = repository
        self.moduleRepository = moduleRepository
        listCalendar = ListStudyCalendarUseCase(repository: repository)
        importEvents = ImportCalendarEventsUseCase(repository: repository)
        linkEvent = LinkCalendarEventToModuleUseCase(repository: repository)
    }

    func load() {
        do {
            let result = try listCalendar()
            events = result.events
            sources = result.sources.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            modules = try moduleRepository.all().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFile(at url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let standardizedURL = url.standardizedFileURL
            let existing = sources.first { $0.kind == .file && $0.url?.standardizedFileURL == standardizedURL }
            let source = CalendarSource(id: existing?.id ?? UUID(),
                                        name: url.deletingPathExtension().lastPathComponent,
                                        url: standardizedURL, lastSyncedAt: .now, kind: .file)
            let parsed = try ICalendarParser.parse(data, sourceID: source.id)
            try importEvents(source: source, events: parsed)
            statusMessage = "\(parsed.count) Termine importiert."
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func subscribe() async {
        guard let url = URL(string: subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host != nil else {
            errorMessage = StudyCalendarError.invalidSubscriptionURL.localizedDescription
            return
        }
        let existing = sources.first { $0.kind == .subscription && $0.url == url }
        let source = CalendarSource(id: existing?.id ?? UUID(),
                                    name: url.deletingPathExtension().lastPathComponent.isEmpty ? (url.host ?? "Subscribed calendar") : url.deletingPathExtension().lastPathComponent,
                                    url: url, lastSyncedAt: .now, kind: .subscription)
        await refresh(source: source)
    }

    func refreshSubscription(_ source: CalendarSource) async {
        guard source.kind == .subscription else { return }
        await refresh(source: source)
    }

    private func refresh(source: CalendarSource) async {
        guard let url = source.url else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("text/calendar, text/plain, */*", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let response = response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
                throw URLError(.badServerResponse)
            }
            let parsed = try ICalendarParser.parse(data, sourceID: source.id)
            let updatedSource = CalendarSource(id: source.id, name: source.name, url: url,
                                               lastSyncedAt: .now, kind: .subscription)
            try importEvents(source: updatedSource, events: parsed)
            subscriptionURL = ""
            statusMessage = "Kalender aktualisiert: \(parsed.count) Termine."
            load()
        } catch {
            errorMessage = "Kalender konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    func setModule(event: StudyCalendarEvent, moduleID: UUID?) {
        do {
            try linkEvent(eventID: event.id, moduleID: moduleID)
            selectedEvent = nil
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSource(_ source: CalendarSource) {
        do {
            try repository.deleteSource(id: source.id)
            statusMessage = "Kalenderquelle entfernt."
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
