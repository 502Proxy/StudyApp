import Foundation

/// Loads the menus of the University of Oldenburg's canteens from the Studierendenwerk Oldenburg.
///
/// The Studierendenwerk's menu pages (studierendenwerk-oldenburg.de/essen/speiseplaene-mensen) embed its
/// menu system, which returns a day's menu as HTML for a `POST` with `func=make_spl`. No account is needed.
struct StudierendenwerkOldenburgClient: CanteenService {
    static let endpoint = URL(string: "https://sw-oldenburg-spl56.maxmanager.xyz/inc/ajax-php_konnektor.inc.php")!

    /// The canteens of the university; the IDs are the menu system's location IDs.
    static let universityCanteens = [
        Canteen(id: 2, name: "Mensa Uhlhornsweg", city: "Oldenburg", address: "Campus Haarentor"),
        Canteen(id: 3, name: "Mensa Wechloy", city: "Oldenburg", address: "Campus Wechloy"),
    ]

    var session: URLSession = .shared
    var calendar: Calendar = .current

    func canteens() async throws -> [Canteen] {
        Self.universityCanteens
    }

    func menu(canteenID: Int, on date: Date) async throws -> CanteenMenu {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formBody(locationID: canteenID, date: date, calendar: calendar).utf8)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MensaError.offline
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { throw MensaError.unavailable }
        let isClosed = StudierendenwerkMenuParser.isClosed(html)
        let meals = isClosed ? [] : StudierendenwerkMenuParser.meals(html)
        return CanteenMenu(canteenID: canteenID, date: date, isClosed: isClosed, meals: meals)
    }

    /// The menu system also needs the Mondays of the day's week and of the following week.
    static func formBody(locationID: Int, date: Date, calendar: Calendar) -> String {
        let monday = weekStart(of: date, calendar: calendar)
        let nextMonday = calendar.date(byAdding: .day, value: 7, to: monday) ?? monday
        return [
            "func=make_spl",
            "locId=\(locationID)",
            "date=\(dayString(date, calendar: calendar))",
            "lang=de",
            "startThisWeek=\(dayString(monday, calendar: calendar))",
            "startNextWeek=\(dayString(nextMonday, calendar: calendar))",
        ].joined(separator: "&")
    }

    /// Monday of the week containing `date`, also for Sundays.
    static func weekStart(of date: Date, calendar: Calendar) -> Date {
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        return mondayFirst.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// `yyyy-MM-dd` in the canteen's (German) time zone.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
