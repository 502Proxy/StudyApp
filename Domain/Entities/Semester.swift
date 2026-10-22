import Foundation

/// Ein Hochschulsemester nach deutscher Zählung: Sommersemester April–September,
/// Wintersemester Oktober bis März des Folgejahres.
struct Semester: Hashable, Comparable, Sendable {
    nonisolated enum Term: String, Sendable {
        case summer = "S"
        case winter = "W"
    }

    let term: Term
    /// Jahr, in dem das Semester beginnt (WiSe 2025/26 → 2025).
    let year: Int

    // `nonisolated`, weil SwiftData-Modelle (nicht auf dem Main Actor) Semester aus der Datenbank lesen.
    nonisolated init(term: Term, year: Int) {
        self.term = term
        self.year = year
    }

    init(containing date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 2000
        switch components.month ?? 1 {
        case 4...9: self.init(term: .summer, year: year)
        case 10...12: self.init(term: .winter, year: year)
        default: self.init(term: .winter, year: year - 1)
        }
    }

    // MARK: Darstellung

    /// „SoSe 2026“ bzw. „WiSe 2025/26“.
    var title: String {
        switch term {
        case .summer: "SoSe \(year)"
        case .winter: "WiSe \(year)/\(String(format: "%02d", (year + 1) % 100))"
        }
    }

    /// „Sommersemester 2026“ bzw. „Wintersemester 2025/26“.
    var longTitle: String {
        switch term {
        case .summer: "Sommersemester \(year)"
        case .winter: "Wintersemester \(year)/\(String(format: "%02d", (year + 1) % 100))"
        }
    }

    // MARK: Speicherung

    /// Kompakte Form für die Datenbank, z. B. „2025W“.
    nonisolated var rawValue: String { "\(year)\(term.rawValue)" }

    nonisolated init?(rawValue: String) {
        guard let termCharacter = rawValue.last,
              let term = Term(rawValue: String(termCharacter)),
              let year = Int(rawValue.dropLast()) else { return nil }
        self.init(term: term, year: year)
    }

    /// Liest Semesterbezeichnungen, wie Stud.IP oder Prüfungsämter sie verwenden:
    /// „SoSe 2026“, „SS 26“, „Sommersemester 2026“, „WiSe 2025/26“, „WS 2025/2026“, „Wintersemester 25/26“.
    init?(title: String) {
        let text = title.lowercased()
        let term: Term
        if text.contains("winter") || text.range(of: #"\bwi?s(e)?\b"#, options: .regularExpression) != nil {
            term = .winter
        } else if text.contains("sommer") || text.contains("summer")
                    || text.range(of: #"\bs(o)?s(e)?\b"#, options: .regularExpression) != nil {
            term = .summer
        } else {
            return nil
        }
        // Erste Jahreszahl ist das Startjahr, auch bei „2025/26“.
        guard let match = text.range(of: #"\d{2,4}"#, options: .regularExpression),
              var year = Int(text[match]) else { return nil }
        if year < 100 { year += 2000 }
        self.init(term: term, year: year)
    }

    // MARK: Zeitraum

    func start(calendar: Calendar = .current) -> Date {
        let month = term == .summer ? 4 : 10
        return calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
    }

    /// Erster Tag des folgenden Semesters, also exklusives Ende.
    func end(calendar: Calendar = .current) -> Date {
        next.start(calendar: calendar)
    }

    var next: Semester {
        term == .summer ? Semester(term: .winter, year: year) : Semester(term: .summer, year: year + 1)
    }

    var previous: Semester {
        term == .summer ? Semester(term: .winter, year: year - 1) : Semester(term: .summer, year: year)
    }

    static func < (lhs: Semester, rhs: Semester) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.term == .summer && rhs.term == .winter
    }

    /// Semester für Auswahllisten: von `lower` bis `upper`, neueste zuerst.
    static func range(from lower: Semester, to upper: Semester) -> [Semester] {
        guard lower <= upper else { return [] }
        var result: [Semester] = []
        var current = upper
        while current >= lower {
            result.append(current)
            current = current.previous
        }
        return result
    }
}

// MARK: - Codable

/// Encoded as its compact raw value (`"2025W"`), the same form the database uses.
extension Semester: Codable {
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let semester = Semester(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid semester \(rawValue)")
        }
        self = semester
    }

    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
