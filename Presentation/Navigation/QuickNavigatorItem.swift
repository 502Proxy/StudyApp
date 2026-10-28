import Foundation

/// Ein Eintrag im Schnellwechsler („Gehe zu …“).
struct QuickNavigatorItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let moduleColor: ModuleColor?
    let location: NavigationLocation
    /// Gesetzt für Notizen: wird nach dem Sprung in der Notizübersicht ausgewählt.
    var noteID: UUID?
    /// Zusätzlicher Suchtext, der nicht angezeigt wird (z. B. der Notizinhalt).
    var searchContent: String = ""

    /// Text, in dem die Suche nach Teilbegriffen sucht.
    fileprivate var searchableText: String {
        [title, subtitle, searchContent].compactMap { $0 }.joined(separator: " ")
    }

    var isNote: Bool { noteID != nil }
}

enum QuickNavigatorIndex {
    /// Heute, Kalender sowie jedes Modul mit all seinen Bereichen; optional alle Notizen.
    static func items(modules: [StudyModule], notes: [NoteReference] = []) -> [QuickNavigatorItem] {
        var items = [
            QuickNavigatorItem(
                id: "today", title: "Heute", subtitle: "Übersicht und laufende Vorlesung",
                systemImage: "sun.max", moduleColor: nil, location: .today
            ),
            QuickNavigatorItem(
                id: "calendar", title: "Kalender", subtitle: "Termine und Abos",
                systemImage: "calendar", moduleColor: nil, location: .calendar
            ),
            QuickNavigatorItem(
                id: "assignments", title: "Aufgaben", subtitle: "Abgaben aller Module",
                systemImage: "checklist", moduleColor: nil, location: .assignments
            ),
            QuickNavigatorItem(
                id: "exams", title: "Klausuren", subtitle: "Countdown und Lernpläne",
                systemImage: "flag.checkered", moduleColor: nil, location: .exams
            ),
            QuickNavigatorItem(
                id: "grades", title: "Noten & ECTS", subtitle: "Notenschnitt und Leistungspunkte",
                systemImage: "graduationcap", moduleColor: nil, location: .grades
            ),
        ]
        for module in modules {
            for section in ModuleSection.allCases {
                let isOverview = section == .overview
                items.append(
                    QuickNavigatorItem(
                        id: "\(module.id.uuidString)-\(section.rawValue)",
                        title: isOverview ? module.name : "\(module.name) › \(section.title)",
                        subtitle: module.code.nilIfEmpty,
                        systemImage: isOverview ? "books.vertical" : section.systemImage,
                        moduleColor: module.color,
                        location: .module(module.id, section: section)
                    )
                )
            }
        }
        for reference in notes {
            items.append(
                QuickNavigatorItem(
                    id: "note-\(reference.note.id.uuidString)",
                    title: reference.displayTitle,
                    subtitle: [reference.module.name, reference.isModuleNote ? nil : reference.locationLabel]
                        .compactMap { $0 }
                        .joined(separator: " · "),
                    systemImage: "note.text",
                    moduleColor: reference.module.color,
                    location: .module(reference.module.id, section: .notes),
                    noteID: reference.note.id,
                    searchContent: reference.note.content
                )
            )
        }
        return items
    }

    /// Alle Suchbegriffe müssen vorkommen; Groß-/Kleinschreibung und Diakritika werden ignoriert.
    /// Ohne Suchbegriff erscheinen nur Navigationsziele, keine Notizen.
    static func filter(_ items: [QuickNavigatorItem], query: String) -> [QuickNavigatorItem] {
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return items.filter { !$0.isNote } }
        let matches = items.filter { item in
            tokens.allSatisfy { item.searchableText.localizedStandardContains($0) }
        }
        // Navigationsziele vor Notizen, damit „ana“ zuerst das Modul Analysis findet.
        return matches.filter { !$0.isNote } + matches.filter(\.isNote)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
