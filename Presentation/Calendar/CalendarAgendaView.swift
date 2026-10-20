import SwiftUI

/// Chronologische Liste aller Termine ab dem ausgewählten Tag, nach Tagen gruppiert.
struct CalendarAgendaView: View {
    @Bindable var viewModel: StudyCalendarViewModel

    var body: some View {
        let sections = viewModel.agendaSections
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.events) { event in
                        CalendarEventRow(
                            event: event,
                            module: viewModel.module(for: event),
                            color: viewModel.color(for: event),
                            day: section.day
                        ) {
                            viewModel.selectedEvent = event
                        }
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(CalendarFormatting.dayTitle(for: section.day, calendar: viewModel.calendar))
                        .font(.headline)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView(
                    "Keine anstehenden Termine",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("Ab \(viewModel.selectedDate.formatted(date: .long, time: .omitted)) ist nichts eingetragen.")
                )
            }
        }
    }
}

/// Trefferliste der Terminsuche. Ein Klick zeigt den Termin im Monatsraster.
struct CalendarSearchResultsView: View {
    @Bindable var viewModel: StudyCalendarViewModel

    var body: some View {
        let results = viewModel.searchResults
        List {
            Section {
                ForEach(results) { event in
                    CalendarEventRow(
                        event: event,
                        module: viewModel.module(for: event),
                        color: viewModel.color(for: event),
                        day: event.startDate,
                        showsDate: true
                    ) {
                        viewModel.reveal(event)
                    }
                    .listRowSeparator(.hidden)
                }
            } header: {
                Text(StudyCalendarViewModel.eventCountText(results.count) + " gefunden")
                    .font(.headline)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            }
        }
    }
}
