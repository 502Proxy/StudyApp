import Foundation

/// Anki's „Notes in Plain Text“ format: one note per line, fields separated by tabs (or the separator in
/// the `#separator:` header), quoted like CSV when a field contains the separator, a quote or a line
/// break. Files written by StudyApp declare plain text (`#html:false`) and a tags column.
enum AnkiTextFormat {
    static func encode(_ cards: [ExchangedFlashcard]) -> String {
        var lines = ["#separator:tab", "#html:false", "#tags column:3"]
        for card in cards {
            lines.append([card.front, card.back, card.tags.joined(separator: " ")].map(quoted).joined(separator: "\t"))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func decode(_ text: String) -> [ExchangedFlashcard] {
        var separator: Character = "\t"
        var isHTML = true
        var tagsColumn: Int?
        var body: [Substring] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("#"), body.isEmpty else {
                body.append(line)
                continue
            }
            let header = line.dropFirst().lowercased()
            if header.hasPrefix("separator:") {
                separator = Self.separator(String(header.dropFirst("separator:".count)))
            } else if header.hasPrefix("html:") {
                isHTML = header.hasSuffix("true")
            } else if header.hasPrefix("tags column:") {
                tagsColumn = Int(header.dropFirst("tags column:".count).trimmingCharacters(in: .whitespaces))
            }
        }
        return rows(body.joined(separator: "\n"), separator: separator).compactMap { fields in
            guard fields.count >= 2 else { return nil }
            let clean: (String) -> String = { isHTML ? AnkiFieldText.plainText($0) : $0.trimmed }
            let tags = tagsColumn.flatMap { $0 - 1 < fields.count ? fields[$0 - 1] : nil }
            return ExchangedFlashcard(
                front: clean(fields[0]),
                back: clean(fields[1]),
                tags: tags.map { $0.split(separator: " ").map(String.init) } ?? []
            )
        }
    }

    // MARK: Fields

    private static func quoted(_ field: String) -> String {
        guard field.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\"" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func separator(_ name: String) -> Character {
        switch name.trimmingCharacters(in: .whitespaces) {
        case "comma", ",": ","
        case "semicolon", ";": ";"
        case "pipe", "|": "|"
        case "space", " ": " "
        case "colon", ":": ":"
        default: "\t"
        }
    }

    /// Splits CSV-like text into rows of fields; quoted fields may contain separators and line breaks.
    private static func rows(_ text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character?
        func next() -> Character? {
            if let character = pending {
                pending = nil
                return character
            }
            return iterator.next()
        }
        while let character = next() {
            if inQuotes {
                if character == "\"" {
                    let following = next()
                    if following == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        pending = following
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" && field.isEmpty {
                inQuotes = true
            } else if character == separator {
                fields.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" {
                fields.append(field)
                if fields.contains(where: { !$0.isEmpty }) { rows.append(fields) }
                fields = []
                field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field)
        if fields.contains(where: { !$0.isEmpty }) { rows.append(fields) }
        return rows
    }
}

/// Turns an Anki field (HTML with media references and cloze markers) into plain text.
enum AnkiFieldText {
    static func plainText(_ field: String) -> String {
        var text = field.replacingOccurrences(of: #"\[sound:[^\]]*\]"#, with: "", options: .regularExpression)
        // {{c1::Antwort::Hinweis}} → Antwort
        text = text.replacingOccurrences(of: #"\{\{c\d+::(.*?)(::[^}]*)?\}\}"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"<\s*(br|/div|/p|/li)\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return text.trimmed
    }
}
