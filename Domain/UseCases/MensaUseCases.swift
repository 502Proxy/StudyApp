import Foundation

/// Which day's menu is worth showing: after lunch is over, the next day's.
enum MensaSchedule {
    /// Hot meals are served until about 14:15; afterwards the next day is more useful.
    static let lunchEndHour = 15

    static func menuDay(for now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        guard calendar.component(.hour, from: now) >= lunchEndHour else { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}

/// Loads a menu and keeps it for the rest of the day, so „Heute“ does not ask the server on every visit.
@MainActor
final class LoadCanteenMenuUseCase {
    private let service: any CanteenService
    private var cache: [String: CanteenMenu] = [:]

    init(service: any CanteenService) {
        self.service = service
    }

    func callAsFunction(canteenID: Int, day: Date) async throws -> CanteenMenu {
        let key = "\(canteenID)-\(day.timeIntervalSince1970)"
        if let cached = cache[key] { return cached }
        let menu = try await service.menu(canteenID: canteenID, on: day)
        cache = [key: menu]
        return menu
    }
}
