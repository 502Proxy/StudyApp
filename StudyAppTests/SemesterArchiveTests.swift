import Foundation
import Testing
@testable import StudyApp

private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private let berlin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return calendar
}()

@MainActor
struct SemesterTests {
    @Test func dateMapsToGermanSemester() {
        #expect(Semester(containing: date(2026, 4, 1), calendar: berlin) == Semester(term: .summer, year: 2026))
        #expect(Semester(containing: date(2026, 9, 30), calendar: berlin) == Semester(term: .summer, year: 2026))
        #expect(Semester(containing: date(2026, 10, 1), calendar: berlin) == Semester(term: .winter, year: 2026))
        // Januar bis März gehören zum Wintersemester des Vorjahres.
        #expect(Semester(containing: date(2027, 3, 31), calendar: berlin) == Semester(term: .winter, year: 2026))
    }

    @Test func titlesUseCommonAbbreviations() {
        #expect(Semester(term: .summer, year: 2026).title == "SoSe 2026")
        #expect(Semester(term: .winter, year: 2025).title == "WiSe 2025/26")
        #expect(Semester(term: .winter, year: 2099).longTitle == "Wintersemester 2099/00")
    }

    @Test func rawValueRoundTrips() {
        let semester = Semester(term: .winter, year: 2025)
        #expect(semester.rawValue == "2025W")
        #expect(Semester(rawValue: "2025W") == semester)
        #expect(Semester(rawValue: "2026S") == Semester(term: .summer, year: 2026))
        #expect(Semester(rawValue: "") == nil)
        #expect(Semester(rawValue: "abcW") == nil)
    }

    @Test(arguments: [
        ("SoSe 2026", Semester(term: .summer, year: 2026)),
        ("SS 26", Semester(term: .summer, year: 2026)),
        ("Sommersemester 2026", Semester(term: .summer, year: 2026)),
        ("WiSe 2025/26", Semester(term: .winter, year: 2025)),
        ("WS 2025/2026", Semester(term: .winter, year: 2025)),
        ("Wintersemester 25/26", Semester(term: .winter, year: 2025)),
    ])
    func parsesStudIPTitles(title: String, expected: Semester) {
        #expect(Semester(title: title) == expected)
    }

    @Test func unknownTitlesAreRejected() {
        #expect(Semester(title: "Unbegrenzt") == nil)
        #expect(Semester(title: "Sommersemester") == nil)
    }

    @Test func orderingFollowsTime() {
        let summer25 = Semester(term: .summer, year: 2025)
        let winter25 = Semester(term: .winter, year: 2025)
        let summer26 = Semester(term: .summer, year: 2026)
        #expect(summer25 < winter25)
        #expect(winter25 < summer26)
        #expect(summer25.next == winter25)
        #expect(summer26.previous == winter25)
        #expect(Semester.range(from: summer25, to: summer26) == [summer26, winter25, summer25])
    }

    @Test func boundariesAreFirstOfAprilAndOctober() {
        let winter = Semester(term: .winter, year: 2025)
        #expect(winter.start(calendar: berlin) == berlin.date(from: DateComponents(year: 2025, month: 10, day: 1)))
        #expect(winter.end(calendar: berlin) == berlin.date(from: DateComponents(year: 2026, month: 4, day: 1)))
    }
}

@MainActor
struct SemesterArchiveTests {
    private func module(_ name: String, _ semester: Semester, archived: Bool = false, grade: Double? = nil, credits: Double? = nil) -> StudyModule {
        StudyModule(
            id: UUID(), name: name, code: "", color: .blue, createdAt: Date(),
            credits: credits, grade: grade, semester: semester, isArchived: archived
        )
    }

    @Test func modulesWithoutSemesterUseCreationDate() {
        let module = StudyModule(id: UUID(), name: "Physik", code: "", color: .teal, createdAt: date(2025, 11))
        #expect(module.semester == Semester(term: .winter, year: 2025))
        #expect(!module.isArchived)
    }

    @Test func groupsAreNewestFirst() {
        let old = module("Analysis I", Semester(term: .winter, year: 2024))
        let current = module("Analysis II", Semester(term: .summer, year: 2025))
        let groups = SemesterOverview.groups([old, current])
        #expect(groups.map(\.semester) == [current.semester, old.semester])
        #expect(groups.first?.modules == [current])
    }

    @Test func finishedSemestersOnlyListActiveModulesOfThePast() {
        let summer25 = Semester(term: .summer, year: 2025)
        let winter24 = Semester(term: .winter, year: 2024)
        let modules = [
            module("Alt, aber aktiv", summer25),
            module("Schon archiviert", winter24, archived: true),
            module("Laufend", Semester(term: .winter, year: 2025)),
        ]
        let finished = SemesterOverview.finishedSemestersWithActiveModules(modules, now: date(2025, 11), calendar: berlin)
        #expect(finished == [summer25])
    }

    @Test func archivingKeepsGradesAndOnlyTouchesChangedModules() throws {
        let repository = FakeModuleRepository()
        let graded = module("Lineare Algebra", Semester(term: .winter, year: 2024), grade: 1.7, credits: 9)
        let archived = module("Programmierung", Semester(term: .winter, year: 2024), archived: true, grade: 2.3, credits: 6)
        repository.storage = [graded, archived]

        let changed = try SetModulesArchivedUseCase(repository: repository)([graded, archived], archived: true)

        #expect(changed == 1)
        #expect(repository.storage.allSatisfy { $0.isArchived })
        #expect(repository.storage.first?.grade == 1.7)
        // Archivierte Module zählen weiter zum Schnitt: (1,7·9 + 2,3·6) / 15 = 1,94
        let average = try #require(GradeSummary(modules: repository.storage).weightedAverage)
        #expect(abs(average - 1.94) < 0.001)
    }

    @Test func updateCanChangeSemesterAndArchiveState() throws {
        let repository = FakeModuleRepository()
        let created = try CreateModuleUseCase(repository: repository)(
            name: "Statistik", code: "", color: .amber, semester: Semester(term: .summer, year: 2025)
        )
        #expect(created.semester == Semester(term: .summer, year: 2025))

        let updated = try UpdateModuleUseCase(repository: repository)(
            created, name: "Statistik", code: "", color: .amber,
            semester: Semester(term: .winter, year: 2025), isArchived: true
        )
        #expect(updated.semester == Semester(term: .winter, year: 2025))
        #expect(updated.isArchived)

        // Ohne Angabe bleiben Semester und Archivstatus erhalten.
        let renamed = try UpdateModuleUseCase(repository: repository)(updated, name: "Statistik I", code: "", color: .amber)
        #expect(renamed.semester == updated.semester)
        #expect(renamed.isArchived)
    }
}
