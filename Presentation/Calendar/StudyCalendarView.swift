import SwiftUI
import UniformTypeIdentifiers

struct StudyCalendarView: View {
    @Bindable var viewModel: StudyCalendarViewModel
    let onOpenModule: (UUID) -> Void
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var isImporting = false
    @State private var showSubscriptionHelp = false
    @State private var selectedDate: Date?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 20) {
                monthGrid
                    .frame(maxWidth: .infinity)
                agenda
                    .frame(width: 300)
            }
            .padding(20)
        }
        .background(Theme.background)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [UTType(filenameExtension: "ics") ?? .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { viewModel.importFile(at: url) }
            case .failure(let error): viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $viewModel.selectedEvent) { event in
            CalendarEventDetailSheet(event: event, modules: viewModel.modules,
                                     onSave: { moduleID in viewModel.setModule(event: event, moduleID: moduleID) },
                                     onOpenModule: { moduleID in
                                         viewModel.selectedEvent = nil
                                         onOpenModule(moduleID)
                                     })
        }
        .alert("Kalender", isPresented: Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .alert("Kalender-Abonnement", isPresented: $showSubscriptionHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Füge eine URL zu einem iCalendar-Feed (.ics) ein. Abonnements werden beim Hinzufügen und manuell über das Aktualisieren-Symbol synchronisiert. Wiederkehrende Regeln werden derzeit nicht expandiert.")
        }
        .task { viewModel.load() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kalender").font(.system(size: 24, weight: .semibold))
                Text("Termine und Lernmodule an einem Ort")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth; selectedDate = nil } label: {
                Image(systemName: "chevron.left")
            }.buttonStyle(.bordered)
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.headline).frame(minWidth: 145)
            Button { displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth; selectedDate = nil } label: {
                Image(systemName: "chevron.right")
            }.buttonStyle(.bordered)
            Button("Heute") { displayedMonth = calendar.dateInterval(of: .month, for: .now)?.start ?? .now; selectedDate = nil }
                .buttonStyle(.bordered)
            Menu {
                Button { isImporting = true } label: { Label(".ics-Datei importieren", systemImage: "square.and.arrow.down") }
                Button { showSubscriptionHelp = true } label: { Label("Kalender abonnieren", systemImage: "link") }
            } label: { Label("Kalender hinzufügen", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
        }
        .padding(20)
    }

    private var monthGrid: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                ForEach(monthDates, id: \.self) { date in
                    let inMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
                    Button { selectedDate = date } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(date.formatted(.dateTime.day()))
                                .font(.system(size: 13, weight: calendar.isDateInToday(date) ? .bold : .regular))
                                .foregroundStyle(inMonth ? Theme.textPrimary : Theme.textSecondary.opacity(0.45))
                            let dayEvents = events(on: date)
                            if !dayEvents.isEmpty {
                                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                                Text("\(dayEvents.count) Termin\(dayEvents.count == 1 ? "" : "e")")
                                    .font(.system(size: 9)).lineLimit(1).foregroundStyle(Theme.textSecondary)
                            } else { Spacer(minLength: 8) }
                        }
                        .padding(8).frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
                        .background((selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? calendar.isDateInToday(date)) ? Theme.accent.opacity(0.12) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.surfaceBorder, lineWidth: 0.6))
                    }
                    .buttonStyle(.plain)
                    .disabled(!inMonth)
                    .help(dayEventsTooltip(date))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedDate.map { "Termine am \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "Termine im Monat").font(.headline)
            if visibleAgendaEvents.isEmpty {
                ContentUnavailableView("Keine Termine", systemImage: "calendar.badge.clock", description: Text("Importiere eine .ics-Datei oder abonniere einen Kalender."))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleAgendaEvents) { event in
                            Button { viewModel.selectedEvent = event } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(event.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.leading)
                                    Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                    if let module = viewModel.modules.first(where: { $0.id == event.moduleID }) {
                                        Label(module.name, systemImage: "books.vertical").font(.caption).foregroundStyle(Theme.accent)
                                    } else {
                                        Text("Kein Modul verknüpft").font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(11)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.surfaceBorder, lineWidth: 0.7))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Divider().padding(.vertical, 4)
            HStack {
                Text("Kalenderquellen").font(.headline)
                Spacer()
                Button { isImporting = true } label: { Image(systemName: "square.and.arrow.down") }.buttonStyle(.plain)
            }
            TextField("https://…/calendar.ics", text: $viewModel.subscriptionURL)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Abonnieren") { Task { await viewModel.subscribe() } }
                    .buttonStyle(.borderedProminent).disabled(viewModel.subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Spacer()
            }
            if viewModel.sources.isEmpty {
                Text("Noch keine Kalenderquellen").font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.sources) { source in
                            HStack(spacing: 8) {
                                Image(systemName: source.kind == .subscription ? "link" : "doc.text")
                                    .foregroundStyle(Theme.textSecondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.name).font(.caption.weight(.medium)).lineLimit(1)
                                    if let date = source.lastSyncedAt {
                                        Text("Aktualisiert \(date.formatted(date: .omitted, time: .shortened))")
                                            .font(.system(size: 10)).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                if source.kind == .subscription {
                                    Button { Task { await viewModel.refreshSubscription(source) } } label: { Image(systemName: "arrow.clockwise") }
                                        .buttonStyle(.plain).help("Abonnement aktualisieren")
                                }
                                Button(role: .destructive) { viewModel.deleteSource(source) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.plain).help("Quelle und importierte Termine entfernen")
                            }
                            .padding(8).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }.frame(maxHeight: 130)
            }
            if let status = viewModel.statusMessage {
                Text(status).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var monthDates: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth),
              let days = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let total = Int(ceil(Double(leading + days.count) / 7.0)) * 7
        return (0..<total).compactMap { offset in calendar.date(byAdding: .day, value: offset - leading, to: interval.start) }
    }

    private var monthEvents: [StudyCalendarEvent] {
        events.filter { calendar.isDate($0.startDate, equalTo: displayedMonth, toGranularity: .month) }
    }

    private var events: [StudyCalendarEvent] { viewModel.events }

    private var visibleAgendaEvents: [StudyCalendarEvent] {
        guard let selectedDate else { return monthEvents }
        return events(on: selectedDate)
    }

    private func events(on date: Date) -> [StudyCalendarEvent] {
        events.filter { calendar.isDate($0.startDate, inSameDayAs: date) }
    }

    private func dayEventsTooltip(_ date: Date) -> String {
        events(on: date).map(\.title).joined(separator: "\n")
    }
}

private struct CalendarEventDetailSheet: View {
    let event: StudyCalendarEvent
    let modules: [StudyModule]
    let onSave: (UUID?) -> Void
    let onOpenModule: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedModuleID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(event.title).font(.title2.weight(.semibold))
            Label(event.startDate.formatted(date: .complete, time: .shortened), systemImage: "calendar")
                .foregroundStyle(Theme.textSecondary)
            if event.endDate > event.startDate {
                Text("Bis \(event.endDate.formatted(date: .omitted, time: .shortened))").font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse") }
            if !event.details.isEmpty { ScrollView { Text(event.details).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180) }
            Divider()
            Text("Mit Modul verknüpfen").font(.headline)
            Picker("Modul", selection: $selectedModuleID) {
                Text("Kein Modul").tag(UUID?.none)
                ForEach(modules) { module in Text(module.name).tag(Optional(module.id)) }
            }.labelsHidden()
            HStack {
                Button("Speichern") { onSave(selectedModuleID); dismiss() }.buttonStyle(.borderedProminent)
                if let selectedModuleID, modules.contains(where: { $0.id == selectedModuleID }) {
                    Button("Modul öffnen") { onOpenModule(selectedModuleID); dismiss() }
                }
                Spacer()
                Button("Schließen") { dismiss() }
            }
        }
        .padding(24).frame(minWidth: 430, minHeight: 300)
        .onAppear { selectedModuleID = event.moduleID }
    }
}
