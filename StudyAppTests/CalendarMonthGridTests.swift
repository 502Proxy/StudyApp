import Foundation
import Testing
@testable import StudyApp

struct CalendarMonthGridTests {
    private func makeCalendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        calendar.firstWeekday = firstWeekday
        calendar.locale = Locale(identifier: "de_DE")
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    @Test func gridStartsOnMondayAndCoversWholeWeeks() throws {
        let calendar = makeCalendar(firstWeekday: 2)
        let weeks = CalendarMonthGrid.weeks(for: try date(2026, 10, 16, in: calendar), calendar: calendar)

        #expect(weeks.count == 5)
        #expect(weeks.allSatisfy { $0.count == 7 })
        #expect(weeks.first?.first == (try date(2026, 9, 28, in: calendar)))
        #expect(weeks.last?.last == (try date(2026, 11, 1, in: calendar)))
    }

    @Test func gridStartsOnSundayWhenCalendarDoes() throws {
        let calendar = makeCalendar(firstWeekday: 1)
        let days = CalendarMonthGrid.days(for: try date(2026, 10, 1, in: calendar), calendar: calendar)

        #expect(days.first == (try date(2026, 9, 27, in: calendar)))
        #expect(days.last == (try date(2026, 10, 31, in: calendar)))
    }

    @Test func monthThatFitsExactlyNeedsNoExtraDays() throws {
        let calendar = makeCalendar(firstWeekday: 2)
        let days = CalendarMonthGrid.days(for: try date(2027, 2, 10, in: calendar), calendar: calendar)

        #expect(days.count == 28)
        #expect(days.first == (try date(2027, 2, 1, in: calendar)))
    }

    @Test func weekdaySymbolsStartWithTheFirstWeekday() {
        let calendar = makeCalendar(firstWeekday: 2)
        let symbols = CalendarMonthGrid.weekdaySymbols(calendar: calendar)

        #expect(symbols.count == 7)
        #expect(symbols.first == calendar.shortStandaloneWeekdaySymbols[1])
        #expect(symbols.last == calendar.shortStandaloneWeekdaySymbols[0])
    }

    @Test func startOfMonthIsMidnightOfTheFirst() throws {
        let calendar = makeCalendar(firstWeekday: 2)
        let start = CalendarMonthGrid.startOfMonth(containing: try date(2026, 10, 16, in: calendar), calendar: calendar)
        #expect(start == (try date(2026, 10, 1, in: calendar)))
    }
}
