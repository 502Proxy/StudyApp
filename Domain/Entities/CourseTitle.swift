import Foundation

/// Art einer Lehrveranstaltung, abgeleitet aus dem Termintitel.
enum CourseEventKind: String, CaseIterable, Codable, Sendable {
    case lecture
    case exercise
    case tutorial
    case seminar
    case lab
    case exam
    case other

    var label: String {
        switch self {
        case .lecture: "Vorlesung"
        case .exercise: "Übung"
        case .tutorial: "Tutorium"
        case .seminar: "Seminar"
        case .lab: "Praktikum"
        case .exam: "Prüfung"
        case .other: "Termin"
        }
    }

    /// Termine dieser Art deuten auch ohne Wiederholung auf ein Modul hin.
    var indicatesCourse: Bool {
        switch self {
        case .lecture, .exercise, .tutorial, .seminar, .lab: true
        case .exam, .other: false
        }
    }
}

/// Zerlegter Termintitel, z. B. „inf030 Programmierung (Übung)“ → Name „Programmierung“,
/// Kürzel „inf030“, Art Übung. `key` ist der Vergleichsschlüssel: Vorlesung und Übung desselben
/// Fachs bekommen denselben Schlüssel und landen damit im selben Modul.
struct CourseTitle: Equatable, Sendable {
    let key: String
    let name: String
    let code: String?
    let kind: CourseEventKind
}

enum CourseTitleAnalyzer {
    /// Ausgeschriebene Bezeichnungen, die überall im Titel als ganzes Wort erkannt werden.
    private static let fullKeywords: [(CourseEventKind, [String])] = [
        (.lecture, ["vorlesung", "vorlesungen", "lecture", "lectures", "ringvorlesung"]),
        (.exercise, ["übung", "übungen", "uebung", "uebungen", "übungsgruppe", "uebungsgruppe", "globalübung", "großübung", "exercise", "exercises", "hörsaalübung", "rechenübung"]),
        (.tutorial, ["tutorium", "tutorien", "tutorial", "tutorials"]),
        (.seminar, ["seminar", "proseminar", "hauptseminar", "oberseminar", "kolloquium"]),
        (.lab, ["praktikum", "labor", "laborpraktikum", "lab"]),
        (.exam, ["klausur", "nachklausur", "probeklausur", "prüfung", "pruefung", "exam", "examen", "testat"]),
    ]

    /// Kurzformen, die nur als eigenständiger Titelteil gelten, z. B. „Analysis (V)“ oder „Mathe – Ü“.
    private static let abbreviations: [(CourseEventKind, [String])] = [
        (.lecture, ["v", "vl", "vo", "vorl", "vorl."]),
        (.exercise, ["ü", "ue", "üb", "ueb", "ub", "üg", "ex"]),
        (.tutorial, ["tut", "tu", "t"]),
        (.seminar, ["s", "se", "sem", "ps", "hs"]),
        (.lab, ["p", "pr", "prak"]),
        (.exam, ["kl"]),
    ]

    /// Füllwörter wie in „Übung zu Analysis I“.
    private static let fillerWords: Set<String> = ["zu", "zur", "zum", "für", "fuer", "der", "die", "das", "von", "in", "and", "und", "&", "-"]

    static func analyze(_ title: String) -> CourseTitle? {
        var kind: CourseEventKind?
        var code: String?
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // 1. Klammern: Art, Kürzel oder Gruppenangabe herausziehen.
        text = processBrackets(in: text, kind: &kind, code: &code)

        // 2. Titelteile an Trennzeichen: ganze Teile, die nur Art oder Gruppe sind, entfernen.
        let separators = [" - ", " – ", " — ", ": ", " | ", ", ", "; ", " · "]
        var parts = [text]
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        var kept: [String] = []
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—|,;·")))
            guard !trimmed.isEmpty else { continue }
            if let detected = Self.kind(forWholePart: trimmed) {
                kind = kind ?? detected
                continue
            }
            if isGroupDesignation(trimmed) { continue }
            if code == nil, isCourseCode(trimmed) {
                code = trimmed
                continue
            }
            kept.append(trimmed)
        }

        // 3. Wörter: Kürzel am Anfang, ausgeschriebene Arten und Gruppenangaben entfernen.
        var words = kept.joined(separator: " ").split(whereSeparator: \.isWhitespace).map(String.init)
        if let first = words.first, code == nil, isCourseCode(first) {
            code = first
            words.removeFirst()
        }
        var cleaned: [String] = []
        var index = 0
        while index < words.count {
            let word = words[index]
            let lower = normalizedWord(word)
            if let detected = fullKeywordKind(lower) {
                kind = kind ?? detected
                // „Übungsgruppe 7“ oder „Tutorium 4“: die Nummer gehört zur Art, nicht zum Namen.
                index += index + 1 < words.count && Int(words[index + 1]) != nil ? 2 : 1
                continue
            }
            // Abkürzung als erstes oder letztes Wort, z. B. „VL Analysis“ oder „Analysis Ü“.
            if index == 0 || index == words.count - 1, lower.count >= 2 || lower == "ü",
               let detected = abbreviationKind(lower), words.count > 1 {
                kind = kind ?? detected
                index += 1
                continue
            }
            if ["gruppe", "gr", "gr.", "group", "grp", "grp."].contains(lower) {
                index += 2 // Bezeichnung samt Nummer überspringen
                continue
            }
            cleaned.append(word)
            index += 1
        }
        // Füllwörter am Anfang und Ende entfernen („Übung zur Analysis“ → „Analysis“).
        while let first = cleaned.first, fillerWords.contains(first.lowercased()) { cleaned.removeFirst() }
        while let last = cleaned.last, fillerWords.contains(last.lowercased()) { cleaned.removeLast() }

        let name = cleaned.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—|,;·/")))
        guard !name.isEmpty else { return nil }
        let key = makeKey(name)
        guard !key.isEmpty else { return nil }
        return CourseTitle(key: key, name: name, code: code, kind: kind ?? .other)
    }

    /// Vergleichsschlüssel: klein, ohne Diakritika und Satzzeichen. Römische Ziffern bleiben erhalten.
    static func makeKey(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
        let scalars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    /// Sucht in einer Terminbeschreibung nach der Veranstaltungsart (z. B. „Art: Vorlesung“ aus Stud.IP).
    static func kind(inDescription text: String) -> CourseEventKind? {
        guard !text.isEmpty else { return nil }
        let words = text.lowercased().split { !$0.isLetter }.map(String.init)
        return words.lazy.compactMap { fullKeywordKind($0) }.first
    }

    // MARK: Erkennung

    private static let bracketExpression = try? NSRegularExpression(pattern: #"[\(\[]([^\)\]]*)[\)\]]"#)

    private static func processBrackets(in text: String, kind: inout CourseEventKind?, code: inout String?) -> String {
        guard let regex = bracketExpression else { return text }
        let source = text as NSString
        var result = text
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)).reversed() {
            let inner = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            var remove = false
            if let detected = Self.kind(forWholePart: inner) {
                kind = kind ?? detected
                remove = true
            } else if isGroupDesignation(inner) || inner.isEmpty {
                remove = true
            } else if isCourseCode(inner) {
                code = code ?? inner
                remove = true
            } else if let detected = inner.split(whereSeparator: { $0.isWhitespace || ",/+&".contains($0) })
                .map({ normalizedWord(String($0)) })
                .lazy.compactMap({ fullKeywordKind($0) ?? abbreviationKind($0) }).first {
                // z. B. „(Vorlesung + Übung)“ oder „(V, Gruppe 2)“
                kind = kind ?? detected
                remove = true
            }
            if remove {
                result = (result as NSString).replacingCharacters(in: match.range, with: " ")
            }
        }
        return result
    }

    private static func normalizedWord(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ":,;()[]"))
    }

    private static func kind(forWholePart part: String) -> CourseEventKind? {
        let lower = normalizedWord(part)
        if let kind = fullKeywordKind(lower) ?? abbreviationKind(lower) { return kind }
        // z. B. „Übung 3“ oder „Vorlesung 12“
        let words = lower.split(separator: " ").map(String.init)
        if words.count == 2, Int(words[1]) != nil, let kind = fullKeywordKind(words[0]) ?? abbreviationKind(words[0]) {
            return kind
        }
        return nil
    }

    private static func fullKeywordKind(_ word: String) -> CourseEventKind? {
        fullKeywords.first { $0.1.contains(word) }?.0
    }

    private static func abbreviationKind(_ word: String) -> CourseEventKind? {
        abbreviations.first { $0.1.contains(word) }?.0
    }

    private static func isGroupDesignation(_ text: String) -> Bool {
        let pattern = #"^(gruppe|gr\.?|group|grp\.?|g)\s*[a-z0-9]{1,3}$"#
        return text.lowercased().range(of: pattern, options: .regularExpression) != nil
    }

    /// Typische Modulkürzel wie „inf030“, „MAT-101“, „PHY 1a“ oder Nummern wie „2.01.123“.
    static func isCourseCode(_ text: String) -> Bool {
        let patterns = [
            #"^[A-Za-zÄÖÜäöü]{2,6}[-_ ]?\d{2,4}[A-Za-z]?$"#,
            #"^\d{1,3}(\.\d{1,4}){1,3}[a-z]?$"#,
            #"^\d{5,8}$"#,
        ]
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }
}
