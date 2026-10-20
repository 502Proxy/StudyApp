import SwiftUI

/// Kalender-Bereich: Monatsraster oder Agenda, Tagesdetails als Inspector, Suche und Quellenverwaltung.
struct StudyCalendarView: View {
    @Bindable var viewModel: StudyCalendarViewModel
    let onOpenModule: (UUID, ModuleSection) -> Void

    @State private var isImporting = false
    @State private var isShowingSources = false
    @State private var showsDayInspector = true
    @State private var isDropTargeted = false
    @State private var isDetectingModules = false

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle("Kalender")
            .searchable(text: $viewModel.searchText, placement: .toolbar, prompt: "Termine durchsuchen")
            .toolbar { toolbarContent }
            .inspector(isPresented: inspectorBinding) {
                CalendarDayInspector(viewModel: viewModel)
                    .inspectorColumnWidth(min: 260, ideal: 300, max: 400)
            }
            .overlay(alignment: .bottom) { statusBanner }
            .overlay { dropHighlight }
            .animation(.default, value: viewModel.statusMessage)
            .dropDestination(for: URL.self) { urls, _ in
                let calendars = urls.filter { $0.pathExtension.lowercased() == "ics" }
                guard !calendars.isEmpty else { return false }
                viewModel.importFiles(calendars)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .calendarFileImporter(isPresented: $isImporting, viewModel: viewModel)
            .sheet(item: $viewModel.selectedEvent) { event in
                CalendarEventDetailSheet(
                    event: event,
                    modules: viewModel.modules,
                    color: viewModel.color(for: event),
                    seriesCount: viewModel.seriesEvents(for: event).count,
                    onLink: { viewModel.link(event, to: $0, applyToSeries: $1) },
                    onOpenModule: { moduleID, section in
                        viewModel.selectedEvent = nil
                        onOpenModule(moduleID, section)
                    }
                )
            }
            .sheet(isPresented: $isShowingSources) {
                CalendarSourcesSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $isDetectingModules) {
                ModuleDetectionSheet(viewModel: viewModel)
            }
            .errorAlert("Kalender", message: viewModel.errorMessage) { viewModel.errorMessage = nil }
    }

    // MARK: Inhalt

    @ViewBuilder
    private var content: some View {
        if viewModel.isEmpty {
            VStack(spacing: 18) {
                EmptyStateView(
                    title: "Stundenplan hinzufügen",
                    systemImage: "calendar.badge.plus",
                    message: "Importiere deinen Stundenplan als .ics-Datei oder abonniere den Kalender-Link deiner Uni (Stud.IP, HISinOne, Moodle …). Module werden daraus automatisch angelegt. Dateien kannst du auch hierher ziehen."
                )
                .frame(maxHeight: 300)
                HStack(spacing: 12) {
                    Button("Datei importieren …") { isImporting = true }
                        .controlSize(.large)
                    Button("Kalender abonnieren …") { isShowingSources = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.isSearching {
            CalendarSearchResultsView(viewModel: viewModel)
        } else {
            switch viewModel.mode {
            case .month: CalendarMonthView(viewModel: viewModel)
            case .agenda: CalendarAgendaView(viewModel: viewModel)
            }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { showsDayInspector && viewModel.mode == .month && !viewModel.isSearching && !viewModel.isEmpty },
            set: { showsDayInspector = $0 }
        )
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Ansicht", selection: $viewModel.mode) {
                ForEach(CalendarViewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
        }
        ToolbarItemGroup {
            Button { viewModel.showMonth(offset: -1) } label: {
                Label("Vorheriger Monat", systemImage: "chevron.left")
            }
            .help("Vorheriger Monat (Bild ↑)")
            Button("Heute") { viewModel.goToToday() }
                .help("Zu heute springen (⇧⌘T)")
            Button { viewModel.showMonth(offset: 1) } label: {
                Label("Nächster Monat", systemImage: "chevron.right")
            }
            .help("Nächster Monat (Bild ↓)")
        }
        ToolbarItem {
            Menu {
                Button { isImporting = true } label: {
                    Label(".ics-Datei importieren …", systemImage: "square.and.arrow.down")
                }
                Button { isShowingSources = true } label: {
                    Label("Kalender abonnieren …", systemImage: "link")
                }
                Divider()
                Button { isDetectingModules = true } label: {
                    Label("Module aus Kalender erkennen …", systemImage: "wand.and.stars")
                }
                .disabled(viewModel.events.isEmpty)
                Button { isShowingSources = true } label: {
                    Label("Quellen verwalten …", systemImage: "list.bullet")
                }
            } label: {
                Label("Kalender hinzufügen", systemImage: "plus")
            }
            .help("Kalender hinzufügen oder verwalten")
        }
        ToolbarItem {
            Button {
                Task { await viewModel.refreshAll() }
            } label: {
                if viewModel.isSyncing {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Abonnements aktualisieren", systemImage: "arrow.clockwise")
                }
            }
            .disabled(!viewModel.hasSubscriptions || viewModel.isSyncing)
            .help("Alle abonnierten Kalender aktualisieren")
        }
        ToolbarItem {
            Button { showsDayInspector.toggle() } label: {
                Label("Tagesdetails", systemImage: "sidebar.right")
            }
            .disabled(viewModel.mode != .month)
            .help("Termine des Tages ein- oder ausblenden")
        }
    }

    // MARK: Overlays

    @ViewBuilder
    private var statusBanner: some View {
        if let message = viewModel.statusMessage {
            StatusToast(message: message)
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 3, dash: [8]))
                .padding(8)
                .allowsHitTesting(false)
        }
    }
}
