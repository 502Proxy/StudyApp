import Foundation

/// Ein Ziel der Seitenleiste.
enum AppDestination: Hashable {
    case today
    case calendar
    case grades
    case module(UUID)
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
    /// Dateibereich der verknüpften Stud.IP-Veranstaltung. Bewusst zuletzt, damit ⌘1–⌘6 gleich bleiben.
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

/// Ein Ort in der App: Ziel plus (bei Modulen) der geöffnete Bereich. Grundlage der Verlaufsliste.
struct NavigationLocation: Hashable {
    var destination: AppDestination
    var section: ModuleSection?

    static let calendar = NavigationLocation(destination: .calendar, section: nil)
    static let today = NavigationLocation(destination: .today, section: nil)
    static let grades = NavigationLocation(destination: .grades, section: nil)

    static func module(_ id: UUID, section: ModuleSection = .overview) -> NavigationLocation {
        NavigationLocation(destination: .module(id), section: section)
    }
}
