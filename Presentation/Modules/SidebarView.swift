import SwiftUI

struct SidebarView: View {
    @Bindable var viewModel: ModulesViewModel
    @Bindable var navigation: AppNavigation
    let calendar: StudyCalendarViewModel
    /// Fällige Karteikarten je Modul, als Zähler neben dem Modulnamen.
    let dueCounts: [UUID: Int]
    /// Open assignments due within a week (or overdue), shown next to „Aufgaben“.
    var dueAssignments = 0
    /// Countdown of the next exam, shown next to „Klausuren“.
    var nextExamCountdown: String?
    let studIP: StudIPViewModel
    let onDetectModules: () -> Void
    let onLinkStudIP: () -> Void
    @State private var pendingDeletion: StudyModule?
    @State private var expandedSemesters: Set<Semester> = []
    /// Weggeklickte Hinweise „Semester ist vorbei“, als Liste von `Semester.rawValue`.
    @AppStorage("sidebar.dismissedSemesterHints") private var dismissedSemesterHints = ""

    /// Brücke zwischen der Listenauswahl und dem zentralen Navigationszustand.
    private var selection: Binding<AppDestination?> {
        Binding(
            get: { navigation.destination },
            set: { navigation.show($0) }
        )
    }

    private var selectedModule: StudyModule? {
        viewModel.modules.first { $0.id == navigation.selectedModuleID }
    }

    var body: some View {
        List(selection: selection) {
            if let lecture = calendar.currentLecture, let module = calendar.module(for: lecture) {
                LiveLectureRow(
                    module: module,
                    event: lecture,
                    referenceDate: calendar.referenceDate,
                    progress: calendar.progress(of: lecture)
                ) {
                    navigation.show(module: module.id, section: .slides, intent: .resumeSlides)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                .selectionDisabled()
            }

            Section {
                Label("Heute", systemImage: "sun.max")
                    .tag(AppDestination.today)
                Label("Kalender", systemImage: "calendar")
                    .badge(calendar.todayEventCount)
                    .tag(AppDestination.calendar)
                Label("Aufgaben", systemImage: "checklist")
                    .badge(dueAssignments)
                    .tag(AppDestination.assignments)
                Label("Klausuren", systemImage: "flag.checkered")
                    .badge(nextExamCountdown.map { Text($0) })
                    .tag(AppDestination.exams)
                Label("Noten & ECTS", systemImage: "graduationcap")
                    .tag(AppDestination.grades)
                Label("Statistik", systemImage: "chart.bar")
                    .tag(AppDestination.statistics)
            }

            Section {
                if viewModel.modules.isEmpty {
                    emptyModulesRow
                }
                ForEach(semesterHints, id: \.self) { semester in
                    FinishSemesterRow(semester: semester) {
                        viewModel.setArchived(semester: semester, true)
                    } onDismiss: {
                        dismissedSemesterHints += " \(semester.rawValue)"
                    }
                }
                ForEach(viewModel.activeModules) { module in
                    moduleRow(module)
                }
            } header: {
                HStack {
                    Text("Module")
                    Spacer()
                    Menu {
                        Button("Neues Modul …", systemImage: "plus") { viewModel.editorMode = .create }
                        Button("Module aus Kalender erkennen …", systemImage: "wand.and.stars", action: onDetectModules)
                            .disabled(calendar.events.isEmpty)
                        Divider()
                        Button("Stud.IP-Veranstaltungen zuordnen …", systemImage: "link", action: onLinkStudIP)
                        Button("Folien aus Stud.IP laden", systemImage: "arrow.down.doc") {
                            Task { await studIP.syncNow() }
                        }
                        .disabled(!studIP.isConnected || studIP.isSyncing)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Modul hinzufügen")
                }
            }

            if !viewModel.archivedGroups.isEmpty {
                Section("Archiv") {
                    ForEach(viewModel.archivedGroups) { group in
                        DisclosureGroup(isExpanded: expansionBinding(for: group.semester)) {
                            ForEach(group.modules) { module in
                                moduleRow(module)
                            }
                        } label: {
                            ArchivedSemesterLabel(group: group)
                                .contextMenu {
                                    Button("Alle Module wiederherstellen") {
                                        viewModel.setArchived(semester: group.semester, false)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if studIP.isConnected {
                StudIPStatusRow(viewModel: studIP)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    viewModel.editorMode = .create
                } label: {
                    Label("Neues Modul", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .help("Neues Modul (⇧⌘N)")
            }
        }
        .onDeleteCommand {
            pendingDeletion = selectedModule
        }
        .confirmationDialog(
            "Modul löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { module in
            Button("„\(module.name)“ löschen", role: .destructive) {
                viewModel.delete(module)
            }
        } message: { _ in
            Text("Das Modul wird mit allen Folien, Notizen, Karteikarten und Lernzetteln entfernt. Kalendertermine bleiben erhalten, und die Veranstaltung wird nicht erneut automatisch angelegt.")
        }
    }

    private func moduleRow(_ module: StudyModule) -> some View {
        ModuleRow(
            module: module,
            isLive: calendar.liveModuleID == module.id,
            dueCount: dueCounts[module.id] ?? 0
        )
        .tag(AppDestination.module(module.id))
        .contextMenu {
            Button("Folien öffnen") {
                navigation.show(module: module.id, section: .slides, intent: .resumeSlides)
            }
            Button("Notizen") {
                navigation.show(module: module.id, section: .notes)
            }
            if module.studIPCourseID != nil {
                Button("Neue Folien aus Stud.IP laden") {
                    Task { await studIP.syncNow(modules: [module]) }
                }
                .disabled(!studIP.isConnected || studIP.isSyncing)
            }
            Divider()
            Button("Bearbeiten …") {
                viewModel.editorMode = .edit(module)
            }
            if module.isArchived {
                Button("Wiederherstellen") { viewModel.setArchived(module, false) }
            } else {
                Button("Archivieren") { viewModel.setArchived(module, true) }
                Button("\(module.semester.title) abschließen") {
                    viewModel.setArchived(semester: module.semester, true)
                }
            }
            Divider()
            Button("Löschen …", role: .destructive) {
                pendingDeletion = module
            }
        }
    }

    private var semesterHints: [Semester] {
        let dismissed = Set(dismissedSemesterHints.split(separator: " ").map(String.init))
        return viewModel.finishedSemesters(now: calendar.referenceDate).filter { !dismissed.contains($0.rawValue) }
    }

    /// Archivierte Semester sind eingeklappt, bis man sie öffnet.
    private func expansionBinding(for semester: Semester) -> Binding<Bool> {
        Binding(
            get: { expandedSemesters.contains(semester) },
            set: { isExpanded in
                if isExpanded { expandedSemesters.insert(semester) } else { expandedSemesters.remove(semester) }
            }
        )
    }

    private var emptyModulesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Noch keine Module")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
            Button("Modul anlegen") {
                viewModel.editorMode = .create
            }
            .buttonStyle(.link)
            if !calendar.events.isEmpty {
                Button("Aus Kalender erkennen", action: onDetectModules)
                    .buttonStyle(.link)
            }
        }
        .padding(.vertical, 4)
        .selectionDisabled()
    }
}

/// One module in the sidebar: colour dot, name and the running or due-cards indicator.
private struct ModuleRow: View {
    let module: StudyModule
    let isLive: Bool
    let dueCount: Int

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(module.color.color)
                .frame(width: 10, height: 10)
                .frame(width: 18)
            Text(module.name)
                .lineLimit(1)
                .help(module.code.isEmpty ? module.name : "\(module.name) · \(module.code)")
            Spacer(minLength: 4)
            if isLive {
                Circle()
                    .fill(Theme.live)
                    .frame(width: 7, height: 7)
                    .help("Läuft gerade")
            } else if dueCount > 0 {
                Text("\(dueCount)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.warning.opacity(0.14), in: Capsule())
                    .help("\(dueCount) Karteikarten fällig")
            }
        }
        .padding(.vertical, 2)
    }
}

/// Compact row at the top of the sidebar while a lecture is running or about to start.
private struct LiveLectureRow: View {
    let module: StudyModule
    let event: StudyCalendarEvent
    let referenceDate: Date
    let progress: Double
    let action: () -> Void

    private var isLive: Bool { event.startDate <= referenceDate }
    private var tint: Color { isLive ? Theme.live : module.color.color }

    private var status: String {
        if isLive {
            let minutes = max(Int(event.endDate.timeIntervalSince(referenceDate) / 60), 0)
            return "Läuft · noch \(minutes) Min."
        }
        return "Gleich · \(event.startDate.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                    Text(status)
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .textCase(.uppercase)
                        .foregroundStyle(isLive ? Theme.live : Theme.textSecondary)
                }
                Text(module.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if isLive {
                    SlimProgressBar(progress: progress, tint: Theme.live)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Folien der Vorlesung öffnen\(event.location.isEmpty ? "" : " · \(event.location)")")
        .accessibilityLabel("\(status), \(module.name). Folien öffnen")
    }
}

/// Stud.IP connection and last sync at the bottom of the sidebar; a click syncs now.
private struct StudIPStatusRow: View {
    let viewModel: StudIPViewModel

    private var status: String {
        if viewModel.sessionExpired { return "Stud.IP · Anmeldung abgelaufen" }
        if viewModel.isSyncing { return "Stud.IP · wird abgeglichen …" }
        guard let lastSync = viewModel.lastSync else { return "Stud.IP verbunden" }
        return "Stud.IP · \(lastSync.formatted(.relative(presentation: .named)))"
    }

    private var tint: Color {
        viewModel.sessionExpired ? Theme.warning : Theme.success
    }

    var body: some View {
        Button {
            Task { await viewModel.syncNow() }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSyncing {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle()
                        .fill(tint)
                        .frame(width: 7, height: 7)
                }
                Text(status)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(Theme.Typography.small)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSyncing || viewModel.sessionExpired)
        .help(viewModel.sessionExpired ? "In den Einstellungen erneut anmelden" : "Jetzt mit Stud.IP abgleichen")
        .overlay(alignment: .top) { Divider() }
    }
}

/// Hinweis in der Seitenleiste, wenn ein Semester vorbei ist und seine Module noch aktiv sind.
private struct FinishSemesterRow: View {
    let semester: Semester
    let action: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "archivebox")
                .foregroundStyle(Theme.accentText)
            Text("\(semester.title) ist vorbei")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Archivieren", action: action)
                .buttonStyle(.link)
                .font(Theme.Typography.small)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hinweis ausblenden")
        }
        .padding(.vertical, 2)
        .selectionDisabled()
        .help("Module aus dem \(semester.longTitle) ins Archiv verschieben. Noten und ECTS bleiben im Schnitt.")
    }
}

private struct ArchivedSemesterLabel: View {
    let group: SemesterOverview.Group

    var body: some View {
        HStack {
            Label(group.semester.title, systemImage: "archivebox")
            Spacer(minLength: 4)
            if let average = GradeSummary(modules: group.modules).weightedAverage {
                Text("Ø \(GradeScale.format(average))")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
