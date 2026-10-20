import Foundation
import SwiftData
import Testing
@testable import StudyApp

@MainActor
struct StudyCalendarDataTests {
    private func makeEvent(
        source: UUID, externalID: String, title: String = "Termin", allDay: Bool = false
    ) -> StudyCalendarEvent {
        StudyCalendarEvent(
            id: UUID(), externalID: externalID, sourceID: source, title: title, details: "", location: "",
            startDate: Date(timeIntervalSince1970: 1_000_000), endDate: Date(timeIntervalSince1970: 1_003_600),
            moduleID: nil, isAllDay: allDay
        )
    }

    private func makeSource(name: String = "Stundenplan") -> CalendarSource {
        CalendarSource(id: UUID(), name: name, url: nil, lastSyncedAt: nil, kind: .file)
    }

    @Test func replaceEventsAddsUpdatesAndRemovesWhileKeepingModuleLinks() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataStudyCalendarRepository(context: container.mainContext)
            let source = makeSource()
            try repository.save(source: source)

            try repository.replaceEvents(forSource: source.id, with: [
                makeEvent(source: source.id, externalID: "a", title: "Alt"),
                makeEvent(source: source.id, externalID: "b")
            ])
            let moduleID = UUID()
            let stored = try #require(try repository.events().first { $0.externalID == "a" })
            try repository.updateModuleLink(eventID: stored.id, moduleID: moduleID)

            try repository.replaceEvents(forSource: source.id, with: [
                makeEvent(source: source.id, externalID: "a", title: "Neu"),
                makeEvent(source: source.id, externalID: "c")
            ])

            let events = try repository.events()
            #expect(Set(events.map(\.externalID)) == ["a", "c"])
            let updated = try #require(events.first { $0.externalID == "a" })
            #expect(updated.title == "Neu")
            #expect(updated.moduleID == moduleID)
            #expect(updated.id == stored.id)
        }
    }

    @Test func replaceEventsLeavesOtherSourcesUntouched() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataStudyCalendarRepository(context: container.mainContext)
            let first = makeSource(name: "Eins")
            let second = makeSource(name: "Zwei")
            try repository.save(source: first)
            try repository.save(source: second)

            try repository.replaceEvents(forSource: first.id, with: [makeEvent(source: first.id, externalID: "x")])
            try repository.replaceEvents(forSource: second.id, with: [makeEvent(source: second.id, externalID: "x")])
            try repository.replaceEvents(forSource: first.id, with: [makeEvent(source: first.id, externalID: "y")])

            let events = try repository.events()
            #expect(events.filter { $0.sourceID == first.id }.map(\.externalID) == ["y"])
            #expect(events.filter { $0.sourceID == second.id }.map(\.externalID) == ["x"])
        }
    }

    @Test func deleteSourceRemovesItsEvents() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataStudyCalendarRepository(context: container.mainContext)
            let source = makeSource()
            try repository.save(source: source)
            try repository.replaceEvents(forSource: source.id, with: [makeEvent(source: source.id, externalID: "a")])

            try repository.deleteSource(id: source.id)

            #expect(try repository.events().isEmpty)
            #expect(try repository.sources().isEmpty)
        }
    }

    @Test func allDayFlagRoundTrips() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        try withExtendedLifetime(container) {
            let repository = SwiftDataStudyCalendarRepository(context: container.mainContext)
            let source = makeSource()
            try repository.save(source: source)
            try repository.replaceEvents(forSource: source.id, with: [makeEvent(source: source.id, externalID: "a", allDay: true)])

            #expect(try repository.events().first?.isAllDay == true)
        }
    }

    @Test func feedURLNormalizationAcceptsWebcalAndRejectsOtherSchemes() throws {
        #expect(try CalendarFeedURL.normalized(" webcal://example.com/plan.ics ").absoluteString == "https://example.com/plan.ics")
        #expect(try CalendarFeedURL.normalized("http://example.com/a.ics").scheme == "http")
        #expect(throws: StudyCalendarError.invalidSubscriptionURL) { try CalendarFeedURL.normalized("ftp://example.com/a.ics") }
        #expect(throws: StudyCalendarError.invalidSubscriptionURL) { try CalendarFeedURL.normalized("kein link") }
    }
}
