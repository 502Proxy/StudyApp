import Foundation

/// What the widgets show. The app writes it into the shared App Group container; the widget extension
/// only reads it, so widgets never touch the database.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Lecture: Codable, Equatable, Sendable {
        let moduleID: UUID
        let moduleName: String
        let location: String
        let start: Date
        let end: Date
    }

    struct DueModule: Codable, Equatable, Sendable {
        let moduleID: UUID
        let moduleName: String
        let count: Int
    }

    struct Exam: Codable, Equatable, Sendable {
        let moduleID: UUID
        let moduleName: String
        let title: String
        let date: Date
        /// Share of the study plan already done, 0…1.
        let progress: Double
    }

    /// The next few lectures, so the widget timeline can move on without the app.
    var lectures: [Lecture] = []
    var dueModules: [DueModule] = []
    var exams: [Exam] = []

    var dueCards: Int { dueModules.reduce(0) { $0 + $1.count } }

    /// The lecture running at `date`, otherwise the next one.
    func lecture(at date: Date) -> Lecture? {
        lectures.first { $0.end > date }
    }

    /// Moments at which the lecture widget changes: starts and ends of the stored lectures.
    func changeDates(after date: Date) -> [Date] {
        lectures.flatMap { [$0.start, $0.end] }.filter { $0 > date }.sorted()
    }
}

/// Reads and writes the snapshot in the App Group container shared by the app and its widgets.
nonisolated enum WidgetSnapshotStore {
    /// macOS App Group identifiers are prefixed with the team ID.
    static let appGroup = "VF66Y42L4U.germany.oldenburg.mueller.tristan.StudyApp"
    static let fileName = "widget-snapshot.json"

    static var defaultURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: fileName)
    }

    static func load(from url: URL?) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// - Returns: `true` when the stored snapshot changed, so widgets only reload when needed.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot, to url: URL?) throws -> Bool {
        guard let url else { return false }
        guard load(from: url) != snapshot else { return false }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        return true
    }
}

/// Links from widgets into the app: `studyapp://today` or `studyapp://module/<id>/<section>`.
nonisolated enum StudyAppLink: Equatable, Sendable {
    static let scheme = "studyapp"

    case today
    /// `section` is a `ModuleSection` raw value such as `slides`, `flashcards` or `exam`.
    case module(UUID, section: String)

    var url: URL {
        switch self {
        case .today: URL(string: "\(Self.scheme)://today")!
        case .module(let id, let section): URL(string: "\(Self.scheme)://module/\(id.uuidString)/\(section)")!
        }
    }

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        let parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        switch parts.first {
        case "today":
            self = .today
        case "module":
            guard parts.count == 3, let id = UUID(uuidString: parts[1]) else { return nil }
            self = .module(id, section: parts[2])
        default:
            return nil
        }
    }
}
