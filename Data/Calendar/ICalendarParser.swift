import Foundation

/// Small, dependency-free RFC 5545 parser for common VEVENT fields.
/// Recurrence rules are intentionally not expanded; imported DTSTART/DTEND occurrences are preserved.
enum ICalendarParser {
    static func parse(_ data: Data, sourceID: UUID, calendar: Calendar = .current) throws -> [StudyCalendarEvent] {
        guard let text = String(data: data, encoding: .utf8) else { throw StudyCalendarError.invalidCalendarData }
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n\t", with: "")
        let lines = unfolded.components(separatedBy: .newlines)
        var events: [StudyCalendarEvent] = []
        var current: [String: (value: String, parameters: [String: String])]?

        for line in lines {
            if line == "BEGIN:VEVENT" { current = [:]; continue }
            if line == "END:VEVENT" {
                if let fields = current, let event = makeEvent(fields, sourceID: sourceID, calendar: calendar) {
                    events.append(event)
                }
                current = nil
                continue
            }
            guard current != nil, let colon = line.firstIndex(of: ":") else { continue }
            let rawKey = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            let parts = rawKey.split(separator: ";", omittingEmptySubsequences: false)
            let key = String(parts.first ?? "").uppercased()
            var parameters: [String: String] = [:]
            for part in parts.dropFirst() {
                let pair = part.split(separator: "=", maxSplits: 1)
                if pair.count == 2 { parameters[String(pair[0]).uppercased()] = String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            }
            current?[key] = (value, parameters)
        }
        return events
    }

    private static func makeEvent(_ fields: [String: (value: String, parameters: [String: String])],
                                  sourceID: UUID, calendar: Calendar) -> StudyCalendarEvent? {
        guard let startField = fields["DTSTART"], let start = parseDate(startField, calendar: calendar) else { return nil }
        let end = fields["DTEND"].flatMap { parseDate($0, calendar: calendar) } ?? start.addingTimeInterval(3600)
        let uid = fields["UID"]?.value ?? UUID().uuidString
        return StudyCalendarEvent(id: UUID(), externalID: uid, sourceID: sourceID,
                                  title: unescape(fields["SUMMARY"]?.value ?? "Untitled event"),
                                  details: unescape(fields["DESCRIPTION"]?.value ?? ""),
                                  location: unescape(fields["LOCATION"]?.value ?? ""),
                                  startDate: start, endDate: max(start, end), moduleID: nil)
    }

    private static func parseDate(_ field: (value: String, parameters: [String: String]), calendar: Calendar) -> Date? {
        let raw = field.value
        let formats: [(String, TimeZone?)] = [
            ("yyyyMMdd'T'HHmmss'Z'", TimeZone(secondsFromGMT: 0)),
            ("yyyyMMdd'T'HHmmss", field.parameters["TZID"].flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone),
            ("yyyyMMdd'T'HHmm'Z'", TimeZone(secondsFromGMT: 0)),
            ("yyyyMMdd'T'HHmm", field.parameters["TZID"].flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone),
            ("yyyyMMdd", field.parameters["TZID"].flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone)
        ]
        for (format, zone) in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = zone
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static func unescape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
