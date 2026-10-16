import Foundation
import Testing
@testable import StudyApp

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
}
