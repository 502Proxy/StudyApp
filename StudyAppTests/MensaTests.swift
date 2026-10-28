import Foundation
import Testing
@testable import StudyApp

@MainActor
struct StudierendenwerkOldenburgClientTests {
    @Test func offersTheUniversityCanteensWithUhlhornswegFirst() {
        #expect(StudierendenwerkOldenburgClient.universityCanteens.map(\.name) == ["Mensa Uhlhornsweg", "Mensa Wechloy"])
        #expect(StudierendenwerkOldenburgClient.universityCanteens.map(\.id) == [2, 3])
    }

    @Test func asksForTheDayWithTheMondaysOfItsWeekAndTheNext() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let sunday = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 23, minute: 30)))

        let body = StudierendenwerkOldenburgClient.formBody(locationID: 3, date: sunday, calendar: calendar)

        #expect(body == "func=make_spl&locId=3&date=2026-11-01&lang=de&startThisWeek=2026-10-26&startNextWeek=2026-11-02")
    }
}

@MainActor
final class FakeCanteenService: CanteenService {
    var menus: [Int: CanteenMenu] = [:]
    var error: MensaError?
    private(set) var requests = 0

    var canteenList: [Canteen] = []

    func canteens() async throws -> [Canteen] { canteenList }

    func menu(canteenID: Int, on date: Date) async throws -> CanteenMenu {
        requests += 1
        if let error { throw error }
        return menus[canteenID] ?? CanteenMenu(canteenID: canteenID, date: date, isClosed: false, meals: [])
    }
}

@MainActor
struct MensaUseCaseTests {
    @Test func showsTheNextDayAfterLunch() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let morning = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 11)))
        let afternoon = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 16)))

        #expect(MensaSchedule.menuDay(for: morning, calendar: calendar) == calendar.startOfDay(for: morning))
        #expect(calendar.component(.day, from: MensaSchedule.menuDay(for: afternoon, calendar: calendar)) == 29)
    }

    @Test func cachesTheMenuOfADay() async throws {
        let service = FakeCanteenService()
        let load = LoadCanteenMenuUseCase(service: service)
        let day = Date(timeIntervalSince1970: 1_760_000_000)

        _ = try await load(canteenID: 1, day: day)
        _ = try await load(canteenID: 1, day: day)
        #expect(service.requests == 1)

        _ = try await load(canteenID: 2, day: day)
        #expect(service.requests == 2)
    }

    @Test func groupsMealsByCategoryInOrder() {
        let menu = CanteenMenu(canteenID: 1, date: .now, isClosed: false, meals: [
            Meal(id: 1, name: "A", category: "Pasta", studentPrice: nil, notes: []),
            Meal(id: 2, name: "B", category: "Vegan", studentPrice: nil, notes: []),
            Meal(id: 3, name: "C", category: "Pasta", studentPrice: nil, notes: []),
        ])
        #expect(menu.mealsByCategory.map(\.category) == ["Pasta", "Vegan"])
        #expect(menu.mealsByCategory.first?.meals.map(\.name) == ["A", "C"])
    }
}

@MainActor
struct MensaViewModelTests {
    let service = FakeCanteenService()
    let settings = InMemoryStudyPreferences()
    let morning = Date(timeIntervalSince1970: 1_761_642_000) // 28 Oct 2026, 10:00 in Berlin

    private func makeViewModel() throws -> MensaViewModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        return MensaViewModel(service: service, settings: settings, now: { [morning] in morning }, calendar: calendar)
    }

    @Test func staysOffWithoutCanteen() async throws {
        let viewModel = try makeViewModel()
        await viewModel.refresh()
        #expect(viewModel.state == .off)
        #expect(service.requests == 0)
    }

    @Test func showsMealsOrClosedOrUnavailable() async throws {
        let viewModel = try makeViewModel()
        let meal = Meal(id: 1, name: "Gemüsecurry", category: "Vegan", studentPrice: 2.4, notes: [])
        service.menus[7] = CanteenMenu(canteenID: 7, date: viewModel.day, isClosed: false, meals: [meal])

        await viewModel.selectCanteen(7)
        #expect(viewModel.state == .menu(CanteenMenu(canteenID: 7, date: viewModel.day, isClosed: false, meals: [meal])))
        #expect(settings.canteenID == 7)

        service.menus[8] = CanteenMenu(canteenID: 8, date: viewModel.day, isClosed: true, meals: [])
        await viewModel.selectCanteen(8)
        #expect(viewModel.state == .closed)

        service.error = .offline
        await viewModel.selectCanteen(9)
        #expect(viewModel.state == .unavailable(MensaError.offline.localizedDescription))
    }

    @Test func replacesACanteenThatIsNoLongerOffered() async throws {
        service.canteenList = [
            Canteen(id: 2, name: "Mensa Uhlhornsweg", city: "Oldenburg", address: ""),
            Canteen(id: 3, name: "Mensa Wechloy", city: "Oldenburg", address: ""),
        ]
        settings.canteenID = 1084 // chosen from OpenMensa before
        let viewModel = try makeViewModel()

        await viewModel.refresh()
        #expect(settings.canteenID == 2)

        settings.canteenID = 3
        await viewModel.refresh()
        #expect(settings.canteenID == 3)
    }

    @Test func formatsStudentPrices() {
        // The currency style separates the amount with a no-break space.
        #expect(MensaViewModel.priceText(2.5)?.replacingOccurrences(of: "\u{00A0}", with: " ") == "2,50 €")
        #expect(MensaViewModel.priceText(nil) == nil)
    }
}
