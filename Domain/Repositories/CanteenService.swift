import Foundation

/// Port to a canteen menu source (the Studierendenwerk Oldenburg).
@MainActor
protocol CanteenService {
    /// The canteens the source offers menus for, the default one first.
    func canteens() async throws -> [Canteen]
    /// The menu of a canteen on a day. Throws `MensaError.unavailable` when the canteen publishes nothing for it.
    func menu(canteenID: Int, on date: Date) async throws -> CanteenMenu
}
