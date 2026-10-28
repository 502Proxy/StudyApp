import Foundation

/// Loads canteens and menus from the OpenMensa API v2. No account is needed.
struct OpenMensaClient: CanteenService {
    static let baseURL = URL(string: "https://openmensa.org/api/v2/")!

    var session: URLSession = .shared
    var calendar: Calendar = .current

    func canteens(nearLatitude latitude: Double, longitude: Double, radius: Double) async throws -> [Canteen] {
        let data = try await get("canteens", query: [
            URLQueryItem(name: "near[lat]", value: String(latitude)),
            URLQueryItem(name: "near[lng]", value: String(longitude)),
            URLQueryItem(name: "near[dist]", value: String(radius)),
        ])
        return try OpenMensaParser.canteens(data)
    }

    func menu(canteenID: Int, on date: Date) async throws -> CanteenMenu {
        let day = OpenMensaParser.dayString(date, calendar: calendar)
        let isClosed = try OpenMensaParser.isClosed(try await get("canteens/\(canteenID)/days/\(day)"))
        let meals = isClosed ? [] : try OpenMensaParser.meals(try await get("canteens/\(canteenID)/days/\(day)/meals"))
        return CanteenMenu(canteenID: canteenID, date: date, isClosed: isClosed, meals: meals)
    }

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw MensaError.unavailable }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MensaError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw MensaError.unavailable }
        // OpenMensa answers 404 for days without a published menu.
        guard (200...299).contains(http.statusCode) else { throw MensaError.unavailable }
        return data
    }
}
