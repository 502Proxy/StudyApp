import SwiftUI

enum CalendarFormatting {
    /// Überschrift eines Tages, z. B. „Heute · Freitag, 16. Oktober“.
    static func dayTitle(for day: Date, calendar: Calendar = .current) -> String {
        let text = day.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if calendar.isDateInToday(day) { return "Heute · \(text)" }
        if calendar.isDateInTomorrow(day) { return "Morgen · \(text)" }
        return text
    }
}

extension StudyCalendarEvent {
    /// Zeitangabe eines Termins. Mit `day` bezogen auf diesen Tag (relevant für mehrtägige Termine),
    /// ohne `day` mit vollständigem Datum, sobald der Termin mehrere Tage umfasst.
    func timeDescription(on day: Date? = nil, calendar: Calendar = .current) -> String {
        if isAllDay { return "Ganztägig" }
        let start = startDate.formatted(date: .omitted, time: .shortened)
        let end = endDate.formatted(date: .omitted, time: .shortened)

        guard let day else {
            if occupiedDays(calendar: calendar).count > 1 {
                return "\(startDate.formatted(date: .abbreviated, time: .shortened)) – \(endDate.formatted(date: .abbreviated, time: .shortened))"
            }
            return endDate > startDate ? "\(start) – \(end)" : start
        }
        let startsOnDay = calendar.isDate(startDate, inSameDayAs: day)
        let endsOnDay = calendar.isDate(lastActiveInstant, inSameDayAs: day)
        switch (startsOnDay, endsOnDay) {
        case (true, true): return endDate > startDate ? "\(start) – \(end)" : start
        case (true, false): return "ab \(start)"
        case (false, true): return "bis \(end)"
        case (false, false): return "Ganztägig"
        }
    }
}

extension StudyCalendarViewModel {
    /// Farbe eines Termins: die Modulfarbe, sonst neutral.
    func color(for event: StudyCalendarEvent) -> Color {
        module(for: event)?.color.color ?? Color.secondary
    }
}
