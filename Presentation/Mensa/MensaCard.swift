import SwiftUI

/// Today's (or, after lunch, tomorrow's) canteen menu on „Heute“.
struct MensaCard: View {
    let viewModel: MensaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Mensa · \(viewModel.dayTitle)", systemImage: "fork.knife")
            content
        }
        .card()
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .off:
            EmptyView()
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 44)
        case .closed:
            message("Die Mensa hat \(viewModel.dayTitle.lowercased()) geschlossen.", systemImage: "moon.zzz")
        case .unavailable(let text):
            message(text, systemImage: "wifi.slash")
        case .menu(let menu):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(menu.mealsByCategory, id: \.category) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.category)
                            .font(Theme.Typography.overline)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(group.meals) { meal in
                            MealRow(meal: meal)
                        }
                    }
                }
            }
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MealRow: View {
    let meal: Meal

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if !meal.notes.isEmpty {
                    Text(meal.notes.joined(separator: " · "))
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let price = MensaViewModel.priceText(meal.studentPrice) {
                Text(price)
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Canteen choice in the settings.
struct MensaSettingsSection: View {
    let viewModel: MensaViewModel

    private var selection: Binding<Int?> {
        Binding(
            get: { viewModel.canteenID },
            set: { id in Task { await viewModel.selectCanteen(id) } }
        )
    }

    var body: some View {
        Section {
            Picker("Speiseplan auf „Heute“", selection: selection) {
                Text("Aus").tag(Int?.none)
                ForEach(viewModel.canteens) { canteen in
                    Text(canteen.name).tag(Int?.some(canteen.id))
                }
                // Keeps a stored choice visible while the list is still loading or offline.
                if let id = viewModel.canteenID, !viewModel.canteens.contains(where: { $0.id == id }) {
                    Text("Mensa \(id)").tag(Int?.some(id))
                }
            }
            if viewModel.isLoadingCanteens {
                ProgressView().controlSize(.small)
            }
        } header: {
            Text("Mensa")
        } footer: {
            Text("Der Speiseplan kommt von OpenMensa. Nach dem Mittagessen zeigt „Heute“ schon den Plan für morgen.")
        }
        .task { await viewModel.loadCanteens() }
    }
}
