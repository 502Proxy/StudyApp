import Foundation
import Testing
@testable import StudyApp

@MainActor
struct ICalendarParserTests {
    @Test func parsesEventTitleDatesAndEscapedDescription() throws {
        let sourceID = UUID()
        let data = Data("""
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        UID:lecture-1@example.test
        DTSTART:20261020T090000Z
        DTEND:20261020T103000Z
        SUMMARY:Software Engineering
        DESCRIPTION:Bring notes\\nand laptop
        LOCATION:Room 204\\, Building A
        END:VEVENT
        END:VCALENDAR
        """.utf8)

        let events = try ICalendarParser.parse(data, sourceID: sourceID)
        #expect(events.count == 1)
        #expect(events[0].externalID == "lecture-1@example.test")
        #expect(events[0].title == "Software Engineering")
        #expect(events[0].details == "Bring notes\nand laptop")
        #expect(events[0].location == "Room 204, Building A")
        #expect(events[0].endDate.timeIntervalSince(events[0].startDate) == 5_400)
    }

    @Test func unfoldsWrappedLinesAndSkipsInvalidEvents() throws {
        let data = Data("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:folded
        DTSTART:20261020T090000Z
        SUMMARY:Operating Systems
         and Networks
        END:VEVENT
        BEGIN:VEVENT
        UID:missing-date
        SUMMARY:Invalid
        END:VEVENT
        END:VCALENDAR
        """.utf8)

        let events = try ICalendarParser.parse(data, sourceID: UUID())
        #expect(events.count == 1)
        #expect(events[0].title == "Operating Systemsand Networks")
    }

    // MARK: Ganztägige Termine, Zeitzonen und Sonderfälle

    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    @Test func parsesAllDayEventWithExclusiveEnd() throws {
        let data = Data("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:excursion
        DTSTART;VALUE=DATE:20261103
        DTEND;VALUE=DATE:20261105
        SUMMARY:Exkursion
        END:VEVENT
        END:VCALENDAR
        """.utf8)

        let calendar = berlin
        let event = try #require(try ICalendarParser.parse(data, sourceID: UUID(), calendar: calendar).first)
        #expect(event.isAllDay)
        #expect(calendar.dateComponents([.day], from: event.startDate, to: event.endDate).day == 2)
        #expect(event.occupiedDays(calendar: calendar).count == 2)
    }

    @Test func allDayEventWithoutEndLastsOneDay() throws {
        let data = Data("""
        BEGIN:VEVENT
        UID:one-day
        DTSTART;VALUE=DATE:20261103
        SUMMARY:Feiertag
        END:VEVENT
        """.utf8)

        let calendar = berlin
        let event = try #require(try ICalendarParser.parse(data, sourceID: UUID(), calendar: calendar).first)
        #expect(event.occupiedDays(calendar: calendar).count == 1)
    }

    @Test func respectsTimeZoneIdentifier() throws {
        let data = Data("""
        BEGIN:VEVENT
        UID:tz
        DTSTART;TZID=Europe/Berlin:20261020T090000
        DTEND;TZID=Europe/Berlin:20261020T103000
        SUMMARY:Vorlesung
        END:VEVENT
        """.utf8)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let expected = try #require(utc.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 7)))

        let event = try #require(try ICalendarParser.parse(data, sourceID: UUID(), calendar: utc).first)
        #expect(event.startDate == expected)
        #expect(!event.isAllDay)
    }

    @Test func alarmDescriptionDoesNotOverwriteEventDescription() throws {
        let data = Data("""
        BEGIN:VEVENT
        UID:alarm
        DTSTART:20261020T090000Z
        SUMMARY:Vorlesung
        DESCRIPTION:Echte Beschreibung
        BEGIN:VALARM
        ACTION:DISPLAY
        DESCRIPTION:Erinnerung
        END:VALARM
        END:VEVENT
        """.utf8)

        let event = try #require(try ICalendarParser.parse(data, sourceID: UUID()).first)
        #expect(event.details == "Echte Beschreibung")
    }

    @Test func skipsCancelledEvents() throws {
        let data = Data("""
        BEGIN:VEVENT
        UID:cancelled
        DTSTART:20261020T090000Z
        SUMMARY:Ausgefallen
        STATUS:CANCELLED
        END:VEVENT
        """.utf8)

        #expect(try ICalendarParser.parse(data, sourceID: UUID()).isEmpty)
    }

    @Test func eventWithoutUIDGetsAStableExternalID() throws {
        let data = Data("""
        BEGIN:VEVENT
        DTSTART:20261020T090000Z
        SUMMARY:Ohne UID
        END:VEVENT
        """.utf8)

        let first = try #require(try ICalendarParser.parse(data, sourceID: UUID()).first)
        let second = try #require(try ICalendarParser.parse(data, sourceID: UUID()).first)
        #expect(first.externalID == second.externalID)
    }

    @Test func escapedBackslashBeforeNIsNotTurnedIntoANewline() throws {
        let data = Data("""
        BEGIN:VEVENT
        UID:escape
        DTSTART:20261020T090000Z
        SUMMARY:Pfad C:\\\\neu
        END:VEVENT
        """.utf8)

        let event = try #require(try ICalendarParser.parse(data, sourceID: UUID()).first)
        #expect(event.title == "Pfad C:\\neu")
    }
}
