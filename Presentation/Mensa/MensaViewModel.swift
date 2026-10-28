import Foundation
import Observation

/// The canteen menu on „Heute“ and the canteen choice in the settings.
@MainActor
@Observable
final class MensaViewModel {
    enum State: Equatable {
        case off
        case loading
        case closed
        case menu(CanteenMenu)
        case unavailable(String)
    }

    private(set) var state: State = .off
    private(set) var canteens: [Canteen] = []
    private(set) var isLoadingCanteens = false
    /// The day the shown menu is for (today, or tomorrow after lunch).
    private(set) var day: Date

    private let service: any CanteenService
    private let loadMenu: LoadCanteenMenuUseCase
    private let settings: any StudySettingsStore
    private let now: () -> Date
    private let calendar: Calendar

    init(
        service: any CanteenService,
        settings: any StudySettingsStore,
        now: @escaping () -> Date = { .now },
        calendar: Calendar = .current
    ) {
        self.service = service
        self.settings = settings
        self.now = now
        self.calendar = calendar
        loadMenu = LoadCanteenMenuUseCase(service: service)
        day = MensaSchedule.menuDay(for: now(), calendar: calendar)
    }

    var canteenID: Int? { settings.canteenID }
    var isEnabled: Bool { canteenID != nil }

    /// „Heute“ or „Morgen“.
    var dayTitle: String {
        calendar.isDateInToday(day) ? "Heute" : "Morgen"
    }

    func selectCanteen(_ id: Int?) async {
        settings.canteenID = id
        await refresh()
    }

    func refresh() async {
        guard let canteenID else {
            state = .off
            return
        }
        day = MensaSchedule.menuDay(for: now(), calendar: calendar)
        if case .menu(let menu) = state, menu.canteenID == canteenID, menu.date == day { return }
        state = .loading
        do {
            let menu = try await loadMenu(canteenID: canteenID, day: day)
            state = menu.isClosed || menu.meals.isEmpty ? .closed : .menu(menu)
        } catch {
            state = .unavailable(error.localizedDescription)
        }
    }

    /// Canteens around Oldenburg for the settings, nearest first.
    func loadCanteens() async {
        guard canteens.isEmpty, !isLoadingCanteens else { return }
        isLoadingCanteens = true
        defer { isLoadingCanteens = false }
        canteens = (try? await service.canteens(
            nearLatitude: MensaLocation.oldenburgLatitude,
            longitude: MensaLocation.oldenburgLongitude,
            radius: MensaLocation.searchRadius
        )) ?? []
    }

    static func priceText(_ price: Double?) -> String? {
        price.map { $0.formatted(.currency(code: "EUR").locale(Locale(identifier: "de_DE"))) }
    }
}
