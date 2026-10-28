import Foundation

/// Reads OpenMensa API v2 responses (https://openmensa.org/api/v2).
enum OpenMensaParser {
    private struct CanteenDTO: Decodable {
        let id: Int
        let name: String
        let city: String?
        let address: String?
    }

    private struct DayDTO: Decodable {
        let closed: Bool
    }

    private struct MealDTO: Decodable {
        struct Prices: Decodable {
            let students: Double?
        }

        let id: Int
        let name: String
        let category: String?
        let prices: Prices?
        let notes: [String]?
    }

    static func canteens(_ data: Data) throws -> [Canteen] {
        try JSONDecoder().decode([CanteenDTO].self, from: data).map {
            Canteen(id: $0.id, name: $0.name, city: $0.city ?? "", address: $0.address ?? "")
        }
    }

    static func isClosed(_ data: Data) throws -> Bool {
        try JSONDecoder().decode(DayDTO.self, from: data).closed
    }

    static func meals(_ data: Data) throws -> [Meal] {
        try JSONDecoder().decode([MealDTO].self, from: data).map {
            Meal(
                id: $0.id,
                name: $0.name,
                category: $0.category ?? "Essen",
                studentPrice: $0.prices?.students,
                notes: $0.notes ?? []
            )
        }
    }

    /// OpenMensa addresses days as `yyyy-MM-dd` in the canteen's (German) time zone.
    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
