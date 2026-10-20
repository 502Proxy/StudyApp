import Foundation

/// Lädt iCalendar-Feeds per HTTP(S).
struct URLSessionCalendarFeedLoader: CalendarFeedLoader {
    var session: URLSession = .shared

    func load(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("text/calendar, text/plain, */*", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw StudyCalendarError.feedUnavailable(statusCode: http.statusCode)
        }
        return data
    }
}
