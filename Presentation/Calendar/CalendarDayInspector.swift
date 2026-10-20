import SwiftUI

/// Seitenleiste mit den Terminen des ausgewählten Tages.
struct CalendarDayInspector: View {
    @Bindable var viewModel: StudyCalendarViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            if viewModel.selectedDayEvents.isEmpty {
                ContentUnavailableView(
                    "Keine Termine",
                    systemImage: "calendar",
                    description: Text("An diesem Tag steht nichts an.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.selectedDayEvents) { event in
                            CalendarEventRow(
                                event: event,
                                module: viewModel.module(for: event),
                                color: viewModel.color(for: event),
                                day: viewModel.selectedDate
                            ) {
                                viewModel.selectedEvent = event
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.selectedDate, format: .dateTime.weekday(.wide))
                .font(.headline)
            Text(viewModel.selectedDate, format: .dateTime.day().month(.wide).year())
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
