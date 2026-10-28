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

    @Test func runningTimerTakesTheLabelBeforeALecture() {
        let running = MenuBarSummary.StudyTimerStatus(phaseTitle: "Fokus", remainingText: "24:59", isRunning: true)
        let paused = MenuBarSummary.StudyTimerStatus(phaseTitle: "Fokus", remainingText: "12:00", isRunning: false)
        let live = lecture(live: true, time: "noch 38 Min.")

        #expect(MenuBarSummary(lecture: live, dueCards: 0, studyTimer: running).title == "24:59")
        #expect(MenuBarSummary(lecture: live, dueCards: 0, studyTimer: running).symbolName == "timer")
        #expect(MenuBarSummary(lecture: live, dueCards: 0, studyTimer: paused).title == "38 Min.")
        #expect(MenuBarSummary(lecture: live, dueCards: 0, studyTimer: paused).symbolName == "record.circle")
        #expect(MenuBarSummary(lecture: nil, dueCards: 0, studyTimer: paused).symbolName == "graduationcap")
    }

    @Test func timerStatusIsOnlyShownWhileTheTimerIsActive() async {
        let timer = StudyTimerViewModel(
            repository: InMemoryStudySessionRepository(), settings: InMemoryStudyPreferences(), clock: { Date(timeIntervalSince1970: 0) }
        )
        #expect(MenuBarSummary.status(of: timer) == nil)

        await timer.start()
        let status = MenuBarSummary.status(of: timer)
        #expect(status?.isRunning == true)
        #expect(status?.phaseTitle == "Fokus")
        #expect(status?.remainingText == "25:00")

        timer.pause()
        #expect(MenuBarSummary.status(of: timer)?.isRunning == false)
        timer.reset()
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
