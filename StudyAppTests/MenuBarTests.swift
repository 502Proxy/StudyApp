import Foundation
import Testing
@testable import StudyApp

@MainActor
struct MenuBarSummaryTests {
    private func lecture(live: Bool, time: String) -> MenuBarSummary.Lecture {
        MenuBarSummary.Lecture(
            moduleID: UUID(), moduleName: "Analysis I", location: "HS 1", isLive: live, timeText: time, progress: 0.5
        )
    }

    @Test func titleShowsRemainingMinutesOnlyWhileALectureRuns() {
        #expect(MenuBarSummary(lecture: lecture(live: true, time: "noch 38 Min."), dueCards: 3).title == "38 Min.")
        #expect(MenuBarSummary(lecture: lecture(live: false, time: "um 14:15"), dueCards: 3).title.isEmpty)
        #expect(MenuBarSummary(lecture: nil, dueCards: 0).title.isEmpty)
    }

    @Test func startTextSaysTodayTomorrowOrWeekday() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9)))
        let later = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 14, minute: 15)))
        let tomorrow = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: 8)))

        #expect(MenuBarSummary.startText(later, now: now, calendar: calendar).hasPrefix("um "))
        #expect(MenuBarSummary.startText(tomorrow, now: now, calendar: calendar).hasPrefix("morgen "))
    }
}
