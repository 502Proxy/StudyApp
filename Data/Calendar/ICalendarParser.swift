import Foundation

/// Kleiner, abhängigkeitsfreier RFC-5545-Parser für die gängigen VEVENT-Felder.
///
/// Wiederkehrende Termine (`RRULE`) werden in einzelne Termine expandiert, damit Stundenpläne
/// aus Stud.IP, HISinOne & Co. vollständig im Kalender erscheinen. Unterstützt werden
/// `FREQ` (DAILY, WEEKLY, MONTHLY, YEARLY), `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTHDAY`
/// und `BYMONTH`, außerdem `EXDATE` und verschobene Einzeltermine über `RECURRENCE-ID`.
enum ICalendarParser {
    typealias Field = (value: String, parameters: [String: String])

    /// Obergrenze pro Serie, schützt vor fehlerhaften Feeds mit endlosen Regeln.
    static let maximumOccurrences = 1_000

    /// - Parameter referenceDate: Serien ohne Ende werden bis ein Jahr nach diesem Zeitpunkt expandiert.
    static func parse(
        _ data: Data,
        sourceID: UUID,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) throws -> [StudyCalendarEvent] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw StudyCalendarError.invalidCalendarData
        }
        let components = parseComponents(text)
        var context = ParsingContext(calendar: calendar)
        let horizon = referenceDate.addingTimeInterval(366 * 86_400)

        // Verschobene oder geänderte Einzeltermine einer Serie, nach UID gruppiert.
        var overrides: [String: [[String: [Field]]]] = [:]
        var masters: [[String: [Field]]] = []
        for fields in components {
            if fields["RECURRENCE-ID"] != nil, let uid = fields["UID"]?.first?.value {
                overrides[uid, default: []].append(fields)
            } else {
                masters.append(fields)
            }
        }

        var events: [StudyCalendarEvent] = []
        var consumedOverrides = Set<String>()

        for fields in masters {
            guard let base = context.makeEvent(fields, sourceID: sourceID) else { continue }
            let uid = fields["UID"]?.first?.value
            if base.isCancelled {
                // Eine abgesagte Serie nimmt auch ihre Einzelausnahmen mit.
                if let uid { overrides[uid] = nil }
                continue
            }
            guard let ruleValue = fields["RRULE"]?.first?.value,
                  let rule = RecurrenceRule(ruleValue, context: &context, startField: fields["DTSTART"]?.first) else {
                events.append(base.event)
                continue
            }

            let seriesOverrides = uid.map { overrides[$0] ?? [] } ?? []
            let excluded = Set((fields["EXDATE"] ?? []).flatMap { context.parseDateList($0) }.map { context.occurrenceKey(for: $0, isAllDay: base.event.isAllDay) })
            var overrideByKey: [String: [String: [Field]]] = [:]
            for override in seriesOverrides {
                guard let field = override["RECURRENCE-ID"]?.first, let date = context.parseDate(field) else { continue }
                overrideByKey[context.occurrenceKey(for: date, isAllDay: base.event.isAllDay)] = override
            }

            let duration = base.event.endDate.timeIntervalSince(base.event.startDate)
            let dayLength = base.event.isAllDay
                ? max(1, calendar.dateComponents([.day], from: base.event.startDate, to: base.event.endDate).day ?? 1)
                : 0
            let occurrences = rule.occurrences(
                from: base.event.startDate,
                in: context.timeZone(for: fields["DTSTART"]?.first),
                horizon: horizon,
                limit: maximumOccurrences
            )
            for start in occurrences {
                let key = context.occurrenceKey(for: start, isAllDay: base.event.isAllDay)
                guard !excluded.contains(key) else { continue }
                let externalID = "\(base.event.externalID)#\(key)"

                if let override = overrideByKey[key] {
                    consumedOverrides.insert(key)
                    guard let changed = context.makeEvent(override, sourceID: sourceID), !changed.isCancelled else { continue }
                    var event = changed.event
                    event.externalID = externalID
                    events.append(event)
                    continue
                }

                var event = base.event
                event.externalID = externalID
                event.startDate = start
                if base.event.isAllDay {
                    event.endDate = calendar.date(byAdding: .day, value: dayLength, to: start) ?? start.addingTimeInterval(86_400)
                } else {
                    event.endDate = start.addingTimeInterval(duration)
                }
                events.append(event)
            }

            // Ausnahmen, die keinem regulären Vorkommen entsprechen (z. B. außerhalb des Zeitfensters).
            for (key, override) in overrideByKey where !consumedOverrides.contains(key) {
                guard let changed = context.makeEvent(override, sourceID: sourceID), !changed.isCancelled else { continue }
                var event = changed.event
                event.externalID = "\(base.event.externalID)#\(key)"
                events.append(event)
            }
            consumedOverrides.removeAll()
            if let uid { overrides[uid] = nil }
        }

        // Einzelne Ausnahmen ohne zugehörige Serie bleiben als normale Termine erhalten.
        for (_, orphaned) in overrides {
            for fields in orphaned {
                guard let parsed = context.makeEvent(fields, sourceID: sourceID), !parsed.isCancelled else { continue }
                var event = parsed.event
                if let field = fields["RECURRENCE-ID"]?.first, let date = context.parseDate(field) {
                    event.externalID += "#\(context.occurrenceKey(for: date, isAllDay: event.isAllDay))"
                }
                events.append(event)
            }
        }
        return events
    }

    // MARK: Zerlegen

    /// Liefert die Felder aller VEVENTs. Mehrfach vorkommende Eigenschaften (z. B. `EXDATE`) bleiben erhalten.
    static func parseComponents(_ text: String) -> [[String: [Field]]] {
        let unfolded = text.replacingOccurrences(of: "\r\n ", with: "")
            .replacingOccurrences(of: "\n ", with: "")
            .replacingOccurrences(of: "\r\n\t", with: "")
            .replacingOccurrences(of: "\n\t", with: "")

        var components: [[String: [Field]]] = []
        var current: [String: [Field]]?
        var nestedDepth = 0 // Verschachtelte Komponenten wie VALARM haben eigene SUMMARY/DESCRIPTION-Felder.

        for rawLine in unfolded.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            if upper == "BEGIN:VEVENT" {
                current = [:]
                nestedDepth = 0
                continue
            }
            if upper == "END:VEVENT" {
                if let fields = current { components.append(fields) }
                current = nil
                continue
            }
            guard current != nil else { continue }
            if upper.hasPrefix("BEGIN:") { nestedDepth += 1; continue }
            if upper.hasPrefix("END:") { nestedDepth = max(0, nestedDepth - 1); continue }
            guard nestedDepth == 0, let colon = valueSeparator(in: line) else { continue }

            let parts = splitParameters(String(line[..<colon]))
            let key = (parts.first ?? "").uppercased()
            var parameters: [String: String] = [:]
            for part in parts.dropFirst() {
                let pair = part.split(separator: "=", maxSplits: 1)
                if pair.count == 2 {
                    parameters[String(pair[0]).uppercased()] = String(pair[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                }
            }
            current?[key, default: []].append((String(line[line.index(after: colon)...]), parameters))
        }
        return components
    }

    /// Erster Doppelpunkt außerhalb von Anführungszeichen, z. B. bei `ALTREP="https://…"`.
    private static func valueSeparator(in line: String) -> String.Index? {
        var isQuoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" { isQuoted.toggle() }
            if character == ":", !isQuoted { return index }
            index = line.index(after: index)
        }
        return nil
    }

    private static func splitParameters(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var isQuoted = false
        for character in text {
            if character == "\"" { isQuoted.toggle() }
            if character == ";", !isQuoted {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    /// Löst iCalendar-Escapes (`\n`, `\,`, `\;`, `\\`) in einem Durchlauf auf.
    static func unescape(_ value: String) -> String {
        var result = ""
        var iterator = value.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else { result.append(character); continue }
            guard let next = iterator.next() else { result.append(character); break }
            switch next {
            case "n", "N": result.append("\n")
            case ",", ";", "\\": result.append(next)
            default: result.append(character); result.append(next)
            }
        }
        return result
    }
}

// MARK: - Datums- und Termin-Aufbau

/// Hält wiederverwendbare Formatter, damit große Feeds nicht tausende `DateFormatter` erzeugen.
struct ParsingContext {
    let calendar: Calendar
    private var formatters: [String: DateFormatter] = [:]

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    struct ParsedEvent {
        let event: StudyCalendarEvent
        let isCancelled: Bool
    }

    mutating func makeEvent(_ fields: [String: [ICalendarParser.Field]], sourceID: UUID) -> ParsedEvent? {
        guard let startField = fields["DTSTART"]?.first, let start = parseDate(startField) else { return nil }
        // Abgesagte Termine (z. B. ausgefallene Vorlesungen) gehören nicht in den Kalender.
        let isCancelled = fields["STATUS"]?.first?.value.uppercased() == "CANCELLED"

        let isAllDay = Self.isDateOnly(startField)
        let end: Date
        if let endField = fields["DTEND"]?.first, let parsed = parseDate(endField) {
            end = parsed
        } else if let durationValue = fields["DURATION"]?.first?.value,
                  let duration = Self.parseDuration(durationValue) {
            end = isAllDay && duration.days > 0
                ? (calendar.date(byAdding: .day, value: duration.days, to: start) ?? start).addingTimeInterval(duration.seconds)
                : start.addingTimeInterval(TimeInterval(duration.days) * 86_400 + duration.seconds)
        } else if isAllDay {
            end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        } else {
            end = start.addingTimeInterval(3_600)
        }

        let title = ICalendarParser.unescape(fields["SUMMARY"]?.first?.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Ohne UID bleibt die ID stabil, damit Modulverknüpfungen beim Aktualisieren nicht verloren gehen.
        let externalID = fields["UID"]?.first?.value ?? "\(startField.value)|\(title)"
        let event = StudyCalendarEvent(
            id: UUID(), externalID: externalID, sourceID: sourceID,
            title: title.isEmpty ? "Unbenannter Termin" : title,
            details: ICalendarParser.unescape(fields["DESCRIPTION"]?.first?.value ?? ""),
            location: ICalendarParser.unescape(fields["LOCATION"]?.first?.value ?? ""),
            startDate: start, endDate: max(start, end), moduleID: nil, isAllDay: isAllDay
        )
        return ParsedEvent(event: event, isCancelled: isCancelled)
    }

    static func isDateOnly(_ field: ICalendarParser.Field) -> Bool {
        field.parameters["VALUE"]?.uppercased() == "DATE" || (field.value.count == 8 && !field.value.contains("T"))
    }

    func timeZone(for field: ICalendarParser.Field?) -> TimeZone {
        guard let field else { return calendar.timeZone }
        if field.value.hasSuffix("Z") { return TimeZone(identifier: "UTC") ?? calendar.timeZone }
        return field.parameters["TZID"].flatMap(Self.timeZone(named:)) ?? calendar.timeZone
    }

    mutating func parseDate(_ field: ICalendarParser.Field) -> Date? {
        parseDate(field.value, parameters: field.parameters)
    }

    /// `EXDATE` darf mehrere, durch Komma getrennte Zeitpunkte enthalten.
    mutating func parseDateList(_ field: ICalendarParser.Field) -> [Date] {
        field.value.split(separator: ",").compactMap { parseDate(String($0), parameters: field.parameters) }
    }

    private mutating func parseDate(_ value: String, parameters: [String: String]) -> Date? {
        let raw = value.trimmingCharacters(in: .whitespaces)
        let isUTC = raw.hasSuffix("Z")
        let body = isUTC ? String(raw.dropLast()) : raw
        let format: String
        switch body.count {
        case 8: format = "yyyyMMdd"
        case 13: format = "yyyyMMdd'T'HHmm"
        case 15: format = "yyyyMMdd'T'HHmmss"
        default: return nil
        }
        let timeZone: TimeZone
        if isUTC {
            timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        } else if body.count == 8 {
            // Ganztägige Termine gelten im Kalender der Nutzerin bzw. des Nutzers.
            timeZone = calendar.timeZone
        } else {
            timeZone = parameters["TZID"].flatMap(Self.timeZone(named:)) ?? calendar.timeZone
        }
        return formatter(format: format, timeZone: timeZone).date(from: body)
    }

    private mutating func formatter(format: String, timeZone: TimeZone) -> DateFormatter {
        let key = "\(format)|\(timeZone.identifier)"
        if let cached = formatters[key] { return cached }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        formatters[key] = formatter
        return formatter
    }

    /// Stabiler Schlüssel eines Vorkommens, unabhängig von der Zeitzone der Quelle.
    mutating func occurrenceKey(for date: Date, isAllDay: Bool) -> String {
        if isAllDay {
            return formatter(format: "yyyyMMdd", timeZone: calendar.timeZone).string(from: date)
        }
        return formatter(format: "yyyyMMdd'T'HHmmss'Z'", timeZone: TimeZone(identifier: "UTC") ?? .current).string(from: date)
    }

    /// IANA-Namen direkt, gängige Windows-Namen (Outlook/Exchange) über eine kleine Zuordnung.
    static func timeZone(named name: String) -> TimeZone? {
        if let zone = TimeZone(identifier: name) { return zone }
        let windowsNames: [String: String] = [
            "W. Europe Standard Time": "Europe/Berlin",
            "Central Europe Standard Time": "Europe/Budapest",
            "Central European Standard Time": "Europe/Warsaw",
            "Romance Standard Time": "Europe/Paris",
            "GMT Standard Time": "Europe/London",
            "E. Europe Standard Time": "Europe/Chisinau",
            "FLE Standard Time": "Europe/Kiev",
            "UTC": "UTC",
            "Eastern Standard Time": "America/New_York",
            "Pacific Standard Time": "America/Los_Angeles",
        ]
        if let identifier = windowsNames[name] { return TimeZone(identifier: identifier) }
        // Manche Exporte nutzen Präfixe wie "/Europe/Berlin" oder "(UTC+01:00) Berlin".
        let trimmed = name.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        if let zone = TimeZone(identifier: trimmed) { return zone }
        if name.contains("Berlin") || name.contains("Amsterdam") || name.contains("Wien") || name.contains("Vienna") {
            return TimeZone(identifier: "Europe/Berlin")
        }
        return nil
    }

    /// Liest eine RFC-5545-Dauer wie `PT1H30M`, `P1D` oder `P2W`.
    static func parseDuration(_ value: String) -> (days: Int, seconds: TimeInterval)? {
        var text = value.uppercased()
        var sign: Double = 1
        if text.hasPrefix("-") { sign = -1; text.removeFirst() } else if text.hasPrefix("+") { text.removeFirst() }
        guard text.hasPrefix("P") else { return nil }
        text.removeFirst()

        var days = 0
        var seconds: TimeInterval = 0
        var number = ""
        var inTime = false
        for character in text {
            if character == "T" { inTime = true; continue }
            if character.isNumber { number.append(character); continue }
            guard let amount = Int(number) else { return nil }
            number = ""
            switch (character, inTime) {
            case ("W", false): days += amount * 7
            case ("D", false): days += amount
            case ("H", true): seconds += TimeInterval(amount) * 3_600
            case ("M", true): seconds += TimeInterval(amount) * 60
            case ("S", true): seconds += TimeInterval(amount)
            default: return nil
            }
        }
        return (Int(sign) * days, sign * seconds)
    }
}

// MARK: - Wiederholungsregeln

struct RecurrenceRule {
    enum Frequency: String {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
        case yearly = "YEARLY"
    }

    struct WeekdayRule: Equatable {
        /// 1 = Sonntag … 7 = Samstag (wie `Calendar`).
        let weekday: Int
        /// z. B. `1` für "1MO", `-1` für "-1FR", `nil` für jeden passenden Wochentag.
        let ordinal: Int?
    }

    let frequency: Frequency
    let interval: Int
    let count: Int?
    let until: Date?
    let byDay: [WeekdayRule]
    let byMonthDay: [Int]
    let byMonth: [Int]
    let weekStart: Int

    init?(_ value: String, context: inout ParsingContext, startField: ICalendarParser.Field?) {
        var parts: [String: String] = [:]
        for pair in value.split(separator: ";") {
            let keyValue = pair.split(separator: "=", maxSplits: 1)
            guard keyValue.count == 2 else { continue }
            parts[String(keyValue[0]).uppercased()] = String(keyValue[1])
        }
        guard let frequencyValue = parts["FREQ"]?.uppercased(), let frequency = Frequency(rawValue: frequencyValue) else {
            return nil
        }
        self.frequency = frequency
        interval = max(1, Int(parts["INTERVAL"] ?? "") ?? 1)
        count = parts["COUNT"].flatMap(Int.init).map { max(0, $0) }
        if let untilValue = parts["UNTIL"] {
            var parameters: [String: String] = [:]
            if let tzid = startField?.parameters["TZID"], !untilValue.hasSuffix("Z") { parameters["TZID"] = tzid }
            var until = context.parseDate((value: untilValue, parameters: parameters))
            // Ein UNTIL als reines Datum schließt den ganzen Tag ein.
            if untilValue.count == 8, let date = until {
                until = context.calendar.date(byAdding: .day, value: 1, to: date)?.addingTimeInterval(-1)
            }
            self.until = until
        } else {
            until = nil
        }
        byDay = (parts["BYDAY"] ?? "").split(separator: ",").compactMap { Self.weekdayRule(String($0)) }
        byMonthDay = (parts["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }.filter { $0 != 0 && abs($0) <= 31 }
        byMonth = (parts["BYMONTH"] ?? "").split(separator: ",").compactMap { Int($0) }.filter { (1...12).contains($0) }
        weekStart = parts["WKST"].flatMap { Self.weekday(from: $0) } ?? 2
    }

    private static func weekday(from code: String) -> Int? {
        switch code.uppercased() {
        case "SU": 1
        case "MO": 2
        case "TU": 3
        case "WE": 4
        case "TH": 5
        case "FR": 6
        case "SA": 7
        default: nil
        }
    }

    private static func weekdayRule(_ value: String) -> WeekdayRule? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, let weekday = weekday(from: String(trimmed.suffix(2))) else { return nil }
        let prefix = trimmed.dropLast(2)
        return WeekdayRule(weekday: weekday, ordinal: prefix.isEmpty ? nil : Int(prefix))
    }

    /// Alle Startzeitpunkte der Serie, beginnend mit `start`. Die Uhrzeit bleibt in `timeZone` konstant,
    /// sodass Vorlesungen auch über die Zeitumstellung hinweg zur gleichen Ortszeit liegen.
    func occurrences(from start: Date, in timeZone: TimeZone, horizon: Date, limit: Int) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = weekStart

        let time = calendar.dateComponents([.hour, .minute, .second], from: start)
        let end = min(until ?? .distantFuture, count == nil ? horizon : .distantFuture)
        let maximum = min(count ?? limit, limit)
        guard maximum > 0 else { return [] }

        var results: [Date] = [start]
        var period = 0
        let maximumPeriods = 20_000

        func at(_ day: Date) -> Date? {
            calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
        }

        while results.count < maximum, period < maximumPeriods {
            let candidates: [Date]
            switch frequency {
            case .daily:
                guard let day = calendar.date(byAdding: .day, value: period * interval, to: start) else { return results }
                if day > end { return results }
                let weekdays = Set(byDay.map(\.weekday))
                candidates = filterByMonth([day], calendar: calendar)
                    .filter { weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: $0)) }
            case .weekly:
                guard let anchor = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
                      let weekStartDate = calendar.date(byAdding: .weekOfYear, value: period * interval, to: anchor) else { return results }
                if weekStartDate > end { return results }
                let weekdays = byDay.isEmpty ? [calendar.component(.weekday, from: start)] : byDay.map(\.weekday)
                candidates = filterByMonth(weekdays.compactMap { weekday in
                    let offset = (weekday - weekStart + 7) % 7
                    return calendar.date(byAdding: .day, value: offset, to: weekStartDate).flatMap(at)
                }, calendar: calendar)
            case .monthly:
                guard let anchor = calendar.dateInterval(of: .month, for: start)?.start,
                      let month = calendar.date(byAdding: .month, value: period * interval, to: anchor) else { return results }
                if month > end { return results }
                candidates = filterByMonth(daysInMonth(month, start: start, calendar: calendar).compactMap(at), calendar: calendar)
            case .yearly:
                guard let anchor = calendar.dateInterval(of: .year, for: start)?.start,
                      let year = calendar.date(byAdding: .year, value: period * interval, to: anchor) else { return results }
                if year > end { return results }
                let months = byMonth.isEmpty ? [calendar.component(.month, from: start)] : byMonth
                var days: [Date] = []
                for monthNumber in months {
                    guard let month = calendar.date(byAdding: .month, value: monthNumber - 1, to: year) else { continue }
                    if byDay.isEmpty && byMonthDay.isEmpty {
                        let day = calendar.component(.day, from: start)
                        if let date = calendar.date(bySetting: .day, value: day, of: month),
                           calendar.component(.month, from: date) == calendar.component(.month, from: month) {
                            days.append(date)
                        }
                    } else {
                        days.append(contentsOf: daysInMonth(month, start: start, calendar: calendar))
                    }
                }
                candidates = days.compactMap(at)
            }

            for candidate in candidates.sorted() where candidate > start {
                if candidate > end { return results }
                results.append(candidate)
                if results.count >= maximum { return results }
            }
            period += 1
        }
        return results
    }

    private func filterByMonth(_ dates: [Date], calendar: Calendar) -> [Date] {
        guard !byMonth.isEmpty else { return dates }
        return dates.filter { byMonth.contains(calendar.component(.month, from: $0)) }
    }

    /// Tage eines Monats gemäß `BYMONTHDAY` bzw. `BYDAY`; ohne beides der Tag des Serienbeginns.
    private func daysInMonth(_ month: Date, start: Date, calendar: Calendar) -> [Date] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let dayCount = range.count
        func day(_ number: Int) -> Date? {
            guard (1...dayCount).contains(number) else { return nil }
            return calendar.date(byAdding: .day, value: number - 1, to: month)
        }

        if !byMonthDay.isEmpty {
            return byMonthDay.compactMap { $0 > 0 ? day($0) : day(dayCount + $0 + 1) }
        }
        if !byDay.isEmpty {
            var result: [Date] = []
            for rule in byDay {
                let matching = (1...dayCount).compactMap(day).filter { calendar.component(.weekday, from: $0) == rule.weekday }
                if let ordinal = rule.ordinal {
                    let index = ordinal > 0 ? ordinal - 1 : matching.count + ordinal
                    if matching.indices.contains(index) { result.append(matching[index]) }
                } else {
                    result.append(contentsOf: matching)
                }
            }
            return result
        }
        return day(calendar.component(.day, from: start)).map { [$0] } ?? []
    }
}

/// Adapter, der den statischen Parser als Port der Domain bereitstellt.
struct ICalendarFeedParser: CalendarEventParsing {
    func parse(_ data: Data, sourceID: UUID) throws -> [StudyCalendarEvent] {
        try ICalendarParser.parse(data, sourceID: sourceID)
    }
}
