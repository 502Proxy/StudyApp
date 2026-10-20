import Foundation

/// Reine Kalenderrechnung für das Monatsraster, unabhängig von SwiftUI und damit testbar.
enum CalendarMonthGrid {
    /// Tagesbeginn des ersten Tags im Monat von `date`.
    static func startOfMonth(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Alle Tage des Rasters: vollständige Wochen vom ersten bis zum letzten Tag des Monats.
    /// Die Woche beginnt gemäß `calendar.firstWeekday` (in Deutschland Montag).
    static func days(for month: Date, calendar: Calendar) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay) else { return [] }

        var days: [Date] = []
        var day = firstWeek.start
        while day < lastWeek.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return days
    }

    /// Die Tage des Rasters, in Wochen zu je sieben Tagen gruppiert.
    static func weeks(for month: Date, calendar: Calendar) -> [[Date]] {
        let days = days(for: month, calendar: calendar)
        return stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    /// Kurze Wochentagsnamen, beginnend mit dem ersten Wochentag des Kalenders.
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
