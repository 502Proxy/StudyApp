import Foundation

/// Port to a canteen menu source (OpenMensa).
@MainActor
protocol CanteenService {
    /// Canteens within `radius` kilometres of a coordinate.
    func canteens(nearLatitude latitude: Double, longitude: Double, radius: Double) async throws -> [Canteen]
    /// The menu of a canteen on a day. Throws `MensaError.unavailable` when the canteen publishes nothing for it.
    func menu(canteenID: Int, on date: Date) async throws -> CanteenMenu
}
