import Foundation
import Testing
@testable import StudyApp

struct StudyCalendarEventTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private func event(
        _ title: String = "Termin",
        from start: Date,
        to end: Date,
        allDay: Bool = false,
        moduleID: UUID? = nil
    ) -> StudyCalendarEvent {
        StudyCalendarEvent(
            id: UUID(), externalID: UUID().uuidString, sourceID: UUID(), title: title,
            details: "", location: "", startDate: start, endDate: end, moduleID: moduleID, isAllDay: allDay
        )
    }

    @Test func eventWithinOneDayOccupiesOneDay() {
        let days = event(from: date(20, 9), to: date(20, 10, 30)).occupiedDays(calendar: calendar)
        #expect(days == [date(20)])
    }

    @Test func eventAcrossMidnightOccupiesBothDays() {
        let days = event(from: date(20, 22), to: date(21, 2)).occupiedDays(calendar: calendar)
        #expect(days == [date(20), date(21)])
    }

    @Test func eventEndingExactlyAtMidnightDoesNotSpillOver() {
        let days = event(from: date(20, 20), to: date(21)).occupiedDays(calendar: calendar)
        #expect(days == [date(20)])
    }

    @Test func allDayEventUsesExclusiveEnd() {
        let days = event(from: date(3, month: 11), to: date(5, month: 11), allDay: true).occupiedDays(calendar: calendar)
        #expect(days == [date(3, month: 11), date(4, month: 11)])
    }

    @Test func zeroLengthEventStillOccupiesItsDay() {
        let days = event(from: date(20, 9), to: date(20, 9)).occupiedDays(calendar: calendar)
        #expect(days == [date(20)])
    }

    @Test func occupiedDaysAreCapped() {
        let days = event(from: date(1), to: date(1, month: 12)).occupiedDays(calendar: calendar, limit: 10)
        #expect(days.count == 10)
    }

    @Test func displayOrderPutsAllDayFirstThenStartTime() {
        let allDay = event("Feiertag", from: date(20), to: date(21), allDay: true)
        let early = event("Früh", from: date(20, 8), to: date(20, 9))
        let late = event("Spät", from: date(20, 14), to: date(20, 15))

        let sorted = [late, early, allDay].sorted(by: StudyCalendarEvent.displayOrder)
        #expect(sorted.map(\.title) == ["Feiertag", "Früh", "Spät"])
    }

    @Test func upcomingSkipsFinishedEventsAndRespectsModuleAndLimit() {
        let module = UUID()
        let past = event("Vorbei", from: date(10, 9), to: date(10, 10), moduleID: module)
        let running = event("Läuft", from: date(16, 9), to: date(16, 18), moduleID: module)
        let later = event("Später", from: date(20, 9), to: date(20, 10), moduleID: module)
        let other = event("Anderes Modul", from: date(18, 9), to: date(18, 10), moduleID: UUID())

        let now = date(16, 12)
        let all = [later, past, other, running]

        #expect(all.upcoming(after: now, limit: 10).map(\.title) == ["Läuft", "Anderes Modul", "Später"])
        #expect(all.upcoming(after: now, moduleID: module, limit: 10).map(\.title) == ["Läuft", "Später"])
        #expect(all.upcoming(after: now, limit: 1).map(\.title) == ["Läuft"])
    }
}
