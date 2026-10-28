import Foundation

/// A destination in the sidebar.
enum AppDestination: Hashable {
    case today
    case calendar
    /// Assignments of all modules.
    case assignments
    /// Upcoming exams of all modules.
    case exams
    case grades
    case module(UUID)

    /// Stable string for `UserDefaults`; modules are stored by their ID.
    var storageKey: String {
        switch self {
        case .today: "today"
        case .calendar: "calendar"
        case .assignments: "assignments"
        case .exams: "exams"
        case .grades: "grades"
        case .module(let id): id.uuidString
        }
    }

    init?(storageKey: String) {
        switch storageKey {
        case "today": self = .today
        case "calendar": self = .calendar
        case "assignments": self = .assignments
        case "exams": self = .exams
        case "grades": self = .grades
        default:
            guard let id = UUID(uuidString: storageKey) else { return nil }
            self = .module(id)
        }
    }
}

/// Einmalige Anweisung an die Modulansicht, z. B. eine Notiz auszuwählen oder Folien zu öffnen.
/// Wird von `ModuleDetailView` ausgeführt und danach verworfen; gehört nicht zum Verlauf.
enum ModuleIntent: Equatable {
    /// Zuletzt gelesenen (sonst neuesten) Foliensatz an der letzten Seite öffnen.
    case resumeSlides
    /// Bestimmten Foliensatz öffnen, optional auf einer Seite (1-basiert).
    case openDocument(UUID, page: Int?)
    /// Notiz im Bereich „Notizen“ auswählen.
    case selectNote(UUID)
    /// Notiz zu einem Vorlesungstermin öffnen bzw. anlegen.
    case lectureNote(start: Date, title: String)
}

/// Die Bereiche innerhalb eines Moduls.
enum ModuleSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case slides
    case notes
    case assignments
    case flashcards
    case studySheets
    /// Files of the linked Stud.IP course.
    case files
    /// Exam countdown and study plan.
    case exam

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .slides: "Folien"
        case .notes: "Notizen"
        case .assignments: "Aufgaben"
        case .flashcards: "Karteikarten"
        case .studySheets: "Lernzettel"
        case .files: "Dateien"
        case .exam: "Klausur"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .slides: "doc.richtext"
        case .notes: "note.text"
        case .assignments: "checklist"
        case .flashcards: "rectangle.stack"
        case .studySheets: "doc.text"
        case .files: "folder"
        case .exam: "flag.checkered"
        }
    }
}

/// The four tabs of a module. Each tab groups one or more `ModuleSection`s; the sections stay the
/// targets of navigation and deep links (resume slides, select a note …), the tabs only group them.
enum ModuleTab: String, CaseIterable, Identifiable {
    case overview
    case material
    case learning
    case assignments

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .material: "Material"
        case .learning: "Lernen"
        case .assignments: "Aufgaben"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .material: "doc.richtext"
        case .learning: "brain.head.profile"
        case .assignments: "checklist"
        }
    }

    /// Sections in this tab, in the order of its segmented control; the first one opens by default.
    var sections: [ModuleSection] {
        switch self {
        case .overview: [.overview, .exam]
        case .material: [.slides, .files]
        case .learning: [.notes, .flashcards, .studySheets]
        case .assignments: [.assignments]
        }
    }
}

extension ModuleSection {
    /// The tab that shows this section.
    var tab: ModuleTab {
        switch self {
        case .overview, .exam: .overview
        case .slides, .files: .material
        case .notes, .flashcards, .studySheets: .learning
        case .assignments: .assignments
        }
    }
}

/// Ein Ort in der App: Ziel plus (bei Modulen) der geöffnete Bereich. Grundlage der Verlaufsliste.
struct NavigationLocation: Hashable {
    var destination: AppDestination
    var section: ModuleSection?

    static let calendar = NavigationLocation(destination: .calendar, section: nil)
    static let today = NavigationLocation(destination: .today, section: nil)
    static let grades = NavigationLocation(destination: .grades, section: nil)
    static let assignments = NavigationLocation(destination: .assignments, section: nil)
    static let exams = NavigationLocation(destination: .exams, section: nil)

    static func module(_ id: UUID, section: ModuleSection = .overview) -> NavigationLocation {
        NavigationLocation(destination: .module(id), section: section)
    }
}
