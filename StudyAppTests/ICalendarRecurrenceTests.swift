import Foundation
import Testing
@testable import StudyApp

@MainActor
struct ICalendarRecurrenceTests {
    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        return calendar
    }

    private func parse(_ text: String, reference: Date? = nil) throws -> [StudyCalendarEvent] {
        let referenceDate = reference ?? berlin.date(from: DateComponents(year: 2026, month: 10, day: 19)) ?? Date()
        return try ICalendarParser.parse(Data(text.utf8), sourceID: UUID(), calendar: berlin, referenceDate: referenceDate)
            .sorted { $0.startDate < $1.startDate }
    }

    private func local(_ date: Date) -> DateComponents {
        berlin.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    @Test func everyOccurrenceHasItsOwnID() throws {
        let events = try parse("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:ana
        DTSTART:20261013T080000Z
        DTEND:20261013T093000Z
        RRULE:FREQ=WEEKLY;COUNT=6
        SUMMARY:Analysis I
        END:VEVENT
        END:VCALENDAR
        """)
        #expect(events.count == 6)
        // Die Datenbank speichert Termine eindeutig nach ID – gleiche IDs ließen nur einen übrig.
        #expect(Set(events.map(\.id)).count == 6)
        #expect(Set(events.map(\.externalID)).count == 6)
    }

    @Test func weeklyLectureIsExpandedWithExceptionsAndMovedOccurrences() throws {
        let events = try parse("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:ana
        DTSTART;TZID=Europe/Berlin:20261013T100000
        DTEND;TZID=Europe/Berlin:20261013T113000
        RRULE:FREQ=WEEKLY;UNTIL=20261103T235959Z;BYDAY=TU,TH
        EXDATE;TZID=Europe/Berlin:20261020T100000
        SUMMARY:Analysis I
        END:VEVENT
        BEGIN:VEVENT
        UID:ana
        RECURRENCE-ID;TZID=Europe/Berlin:20261022T100000
        DTSTART;TZID=Europe/Berlin:20261022T140000
        DTEND;TZID=Europe/Berlin:20261022T153000
        SUMMARY:Analysis I (verlegt)
        END:VEVENT
        END:VCALENDAR
        """)

        // 13., 15., (20. entfällt), 22. verlegt, 27., 29. Okt., 3. Nov.
        #expect(events.count == 6)
        #expect(events.map { local($0.startDate).day } == [13, 15, 22, 27, 29, 3])
        let moved = try #require(events.first { $0.title == "Analysis I (verlegt)" })
        #expect(local(moved.startDate).hour == 14)
        // Nach der Zeitumstellung (25.10.) bleibt die Vorlesung um 10 Uhr Ortszeit.
        #expect(events.filter { $0.title == "Analysis I" }.allSatisfy { local($0.startDate).hour == 10 })
        #expect(events.allSatisfy { $0.endDate.timeIntervalSince($0.startDate) == 5_400 })
        #expect(Set(events.map(\.externalID)).count == events.count)
        #expect(events.allSatisfy { $0.externalID.hasPrefix("ana#") })
    }

    @Test func countLimitsTheSeriesAndDurationReplacesEnd() throws {
        let events = try parse("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:m
        DTSTART:20261105T090000Z
        DURATION:PT2H
        RRULE:FREQ=MONTHLY;BYDAY=1TH;COUNT=3
        SUMMARY:Kolloquium
        END:VEVENT
        END:VCALENDAR
        """)
        #expect(events.count == 3)
        #expect(events.map { local($0.startDate).month } == [11, 12, 1])
        #expect(events.map { local($0.startDate).day } == [5, 3, 7])
        #expect(events.allSatisfy { $0.endDate.timeIntervalSince($0.startDate) == 7_200 })
    }

    @Test func openEndedSeriesStopsAfterAboutAYear() throws {
        let events = try parse("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:daily
        DTSTART:20261019T080000Z
        DTEND:20261019T090000Z
        RRULE:FREQ=DAILY
        SUMMARY:Lerngruppe
        END:VEVENT
        END:VCALENDAR
        """)
        #expect((360...370).contains(events.count))
    }

    @Test func cancelledSeriesIsSkippedEntirely() throws {
        let events = try parse("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:gone
        DTSTART:20261019T080000Z
        RRULE:FREQ=WEEKLY;COUNT=5
        STATUS:CANCELLED
        SUMMARY:Abgesagt
        END:VEVENT
        END:VCALENDAR
        """)
        #expect(events.isEmpty)
    }

    @Test func quotedParameterWithColonDoesNotBreakTheValue() throws {
        let events = try parse("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:q
        DTSTART:20261019T080000Z
        DESCRIPTION;ALTREP="https://example.com/info":Raumänderung beachten
        SUMMARY:Info
        END:VEVENT
        END:VCALENDAR
        """)
        #expect(events.first?.details == "Raumänderung beachten")
    }

    @Test func singleEventsKeepTheirPlainUID() throws {
        let events = try parse("""
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:once
        DTSTART:20261019T080000Z
        SUMMARY:Einmalig
        END:VEVENT
        END:VCALENDAR
        """)
        #expect(events.map(\.externalID) == ["once"])
    }

    @Test func windowsTimeZoneNamesAreMapped() {
        #expect(ParsingContext.timeZone(named: "W. Europe Standard Time")?.identifier == "Europe/Berlin")
        #expect(ParsingContext.timeZone(named: "Europe/Berlin")?.identifier == "Europe/Berlin")
    }

    @Test func durationsAreParsed() {
        #expect(ParsingContext.parseDuration("PT1H30M")?.seconds == 5_400)
        #expect(ParsingContext.parseDuration("P2D")?.days == 2)
        #expect(ParsingContext.parseDuration("P1W")?.days == 7)
        #expect(ParsingContext.parseDuration("X") == nil)
    }
}
