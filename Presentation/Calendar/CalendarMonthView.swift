import SwiftUI

/// Monatsraster mit Terminchips, Tastatursteuerung und Auswahl eines Tages.
struct CalendarMonthView: View {
    @Bindable var viewModel: StudyCalendarViewModel
    @FocusState private var isGridFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.displayedMonth, format: .dateTime.month(.wide).year())
                .font(Theme.Typography.largeTitle)
            weekdayHeader
            grid
        }
        .padding(Theme.Spacing.page - 4)
        .focusable()
        .focused($isGridFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { viewModel.moveSelection(byDays: -1); return .handled }
        .onKeyPress(.rightArrow) { viewModel.moveSelection(byDays: 1); return .handled }
        .onKeyPress(.upArrow) { viewModel.moveSelection(byDays: -7); return .handled }
        .onKeyPress(.downArrow) { viewModel.moveSelection(byDays: 7); return .handled }
        .onKeyPress(.pageUp) { viewModel.showMonth(offset: -1); return .handled }
        .onKeyPress(.pageDown) { viewModel.showMonth(offset: 1); return .handled }
        .onKeyPress(.return) {
            guard let first = viewModel.selectedDayEvents.first else { return .ignored }
            viewModel.selectedEvent = first
            return .handled
        }
        .onAppear { isGridFocused = true }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 1) {
            ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var grid: some View {
        VStack(spacing: 1) {
            ForEach(viewModel.weeks, id: \.self) { week in
                HStack(spacing: 1) {
                    ForEach(week, id: \.self) { day in
                        CalendarDayCell(
                            day: day,
                            dayLabel: dayLabel(for: day),
                            events: viewModel.events(on: day),
                            isInMonth: viewModel.isInDisplayedMonth(day),
                            isSelected: day == viewModel.selectedDate,
                            isToday: day == viewModel.today,
                            color: { viewModel.color(for: $0) },
                            onSelect: {
                                viewModel.select(day)
                                isGridFocused = true
                            },
                            onOpen: { event in
                                viewModel.select(day)
                                viewModel.selectedEvent = event
                            }
                        )
                    }
                }
            }
        }
        .background(Theme.surfaceBorder)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous).strokeBorder(Theme.surfaceBorder) }
        .shadow(color: Theme.shadow.opacity(0.05), radius: 10, y: 3)
    }

    /// Am Monatsersten steht zusätzlich der Monatsname, damit Wechsel im Raster sichtbar bleiben.
    private func dayLabel(for day: Date) -> String {
        viewModel.calendar.component(.day, from: day) == 1
            ? day.formatted(.dateTime.day().month(.abbreviated))
            : day.formatted(.dateTime.day())
    }
}

private struct CalendarDayCell: View {
    let day: Date
    let dayLabel: String
    let events: [StudyCalendarEvent]
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let color: (StudyCalendarEvent) -> Color
    let onSelect: () -> Void
    let onOpen: (StudyCalendarEvent) -> Void

    private static let chipHeight: CGFloat = 19
    private static let headerHeight: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let capacity = max(Int((proxy.size.height - Self.headerHeight) / Self.chipHeight), 0)
            let visibleCount = events.count <= capacity ? events.count : max(capacity - 1, 0)

            VStack(alignment: .leading, spacing: 2) {
                dayNumber
                ForEach(events.prefix(visibleCount)) { event in
                    chip(for: event)
                }
                if events.count > visibleCount {
                    Text("+\(events.count - visibleCount) weitere")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 5)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isSelected ? Theme.accentSoft : (isInMonth ? Theme.surface : Theme.surfaceSecondary))
        .overlay {
            if isSelected { Rectangle().strokeBorder(Theme.accent, lineWidth: 2) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .help(events.map(\.title).joined(separator: "\n"))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(StudyCalendarViewModel.eventCountText(events.count))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var dayNumber: some View {
        Text(dayLabel)
            .font(.callout.weight(isToday ? .bold : .regular).monospacedDigit())
            .foregroundStyle(isToday ? Color.white : (isInMonth ? Theme.textPrimary : Theme.textSecondary.opacity(0.6)))
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 24)
            .background { if isToday { Capsule().fill(Theme.accent) } }
    }

    private func chip(for event: StudyCalendarEvent) -> some View {
        Button { onOpen(event) } label: {
            Text(event.title)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color(event).opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(alignment: .leading) {
                    Capsule().fill(color(event)).frame(width: 2.5).padding(.vertical, 2)
                }
        }
        .buttonStyle(.plain)
    }
}
