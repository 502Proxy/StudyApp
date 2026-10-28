import Foundation
import Testing
@testable import StudyApp

struct OpenMensaParserTests {
    @Test func readsCanteens() throws {
        let json = #"[{"id":1084,"name":"Oldenburg, Mensa Uhlhornsweg","city":"Oldenburg","address":"Uhlhornsweg 49-55, 26129 Oldenburg","coordinates":[53.14,8.18]}]"#
        let canteens = try OpenMensaParser.canteens(Data(json.utf8))
        #expect(canteens == [Canteen(id: 1084, name: "Oldenburg, Mensa Uhlhornsweg", city: "Oldenburg", address: "Uhlhornsweg 49-55, 26129 Oldenburg")])
    }

    @Test func readsMealsWithStudentPriceAndNotes() throws {
        let json = #"""
        [{"id":1,"name":"Spaghetti Bolognese","category":"Pasta","prices":{"students":2.5,"employees":4.1,"pupils":null,"others":5.0},"notes":["Rind"]},
         {"id":2,"name":"Gemüsecurry","category":"Vegan","prices":{"students":null},"notes":[]},
         {"id":3,"name":"Salatbar","prices":null}]
        """#
        let meals = try OpenMensaParser.meals(Data(json.utf8))
        #expect(meals.map(\.studentPrice) == [2.5, nil, nil])
        #expect(meals.map(\.category) == ["Pasta", "Vegan", "Essen"])
        #expect(meals.first?.notes == ["Rind"])
    }

    @Test func readsClosedDaysAndFormatsDates() throws {
        #expect(try OpenMensaParser.isClosed(Data(#"{"date":"2026-10-28","closed":true}"#.utf8)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 23, minute: 30)))
        #expect(OpenMensaParser.dayString(date, calendar: calendar) == "2026-03-09")
    }
}

@MainActor
final class FakeCanteenService: CanteenService {
    var menus: [Int: CanteenMenu] = [:]
    var error: MensaError?
    private(set) var requests = 0

    func canteens(nearLatitude latitude: Double, longitude: Double, radius: Double) async throws -> [Canteen] { [] }

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
