import Foundation

/// A canteen listed by OpenMensa.
struct Canteen: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    var name: String
    var city: String
    var address: String
}

/// One dish on a canteen's menu.
struct Meal: Identifiable, Hashable, Sendable {
    let id: Int
    var name: String
    /// e.g. „Pasta“, „Vegetarisch“, „Pizza“.
    var category: String
    /// Price for students in euros, if the canteen publishes one.
    var studentPrice: Double?
    /// Hints such as „vegan“ or allergens.
    var notes: [String]
}

/// The menu of one canteen on one day.
struct CanteenMenu: Equatable, Sendable {
    let canteenID: Int
    let date: Date
    var isClosed: Bool
    var meals: [Meal]

    /// Meals grouped by category, in the order the canteen lists them.
    var mealsByCategory: [(category: String, meals: [Meal])] {
        var order: [String] = []
        var groups: [String: [Meal]] = [:]
        for meal in meals {
            if groups[meal.category] == nil { order.append(meal.category) }
            groups[meal.category, default: []].append(meal)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

enum MensaError: LocalizedError, Equatable {
    case offline
    case unavailable

    var errorDescription: String? {
        switch self {
        case .offline: "Der Mensaplan ist gerade nicht erreichbar. Bist du online?"
        case .unavailable: "Für diesen Tag gibt es keinen Speiseplan."
        }
    }
}
