import SwiftUI

struct RootView: View {
    @Bindable var viewModel: ModulesViewModel
    @Bindable var navigation: AppNavigation
    let calendarViewModel: StudyCalendarViewModel
    let todayViewModel: TodayViewModel
    @Bindable var assignmentsViewModel: AssignmentsViewModel
    let makeSlidesViewModel: SlidesViewModelFactory
    let makeLearningViewModel: LearningViewModelFactory

    @State private var isDetectingModules = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                viewModel: viewModel,
                navigation: navigation,
                calendar: calendarViewModel,
                dueCounts: todayViewModel.dueCounts,
                overdueAssignments: assignmentsViewModel.overdueCount,
                onDetectModules: { isDetectingModules = true }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 340)
        } detail: {
            detail
        }
        .toolbar { historyButtons }
        .sheet(item: $assignmentsViewModel.editor) { draft in
            AssignmentEditorSheet(
                draft: draft,
                modules: viewModel.modules,
                onSave: { assignmentsViewModel.save($0) },
                onDelete: deleteAction(for: draft)
            )
        }
        .sheet(item: $viewModel.editorMode) { mode in
            ModuleEditorSheet(mode: mode) { draft in
                guard let saved = viewModel.save(draft) else { return false }
                if draft.id == nil {
                    navigation.show(module: saved.id, section: .overview)
                }
                return true
            }
        }
        .sheet(isPresented: $navigation.isQuickNavigatorPresented) {
            QuickNavigatorSheet(modules: viewModel.modules, notes: todayViewModel.notes) { item in
                if let noteID = item.noteID, case .module(let moduleID) = item.location.destination {
                    navigation.show(module: moduleID, section: .notes, intent: .selectNote(noteID))
                } else {
                    navigation.go(to: item.location)
                }
            }
            .onAppear { todayViewModel.load() }
        }
        .sheet(isPresented: $isDetectingModules) {
            ModuleDetectionSheet(viewModel: calendarViewModel)
        }
        .onChange(of: viewModel.modules) { _, modules in
            navigation.prune(validModuleIDs: Set(modules.map(\.id)))
            calendarViewModel.load()
            todayViewModel.load()
        }
        .onChange(of: navigation.destination) { _, destination in
            // Zähler (fällige Karten, Notizen) aktuell halten, wenn man zur Startseite oder in ein Modul wechselt.
            if destination == .today || destination == nil { todayViewModel.load() }
        }
        .overlay(alignment: .bottom) {
            if navigation.destination != .calendar, let message = calendarViewModel.statusMessage {
                StatusToast(message: message, systemImage: "wand.and.stars")
            }
        }
        .animation(.default, value: calendarViewModel.statusMessage)
        .errorAlert(message: viewModel.errorMessage ?? todayViewModel.errorMessage ?? assignmentsViewModel.errorMessage) {
            viewModel.errorMessage = nil
            todayViewModel.errorMessage = nil
            assignmentsViewModel.errorMessage = nil
        }
    }

    // MARK: Detailbereich

    @ViewBuilder
    private var detail: some View {
        switch navigation.destination {
        case .today, nil:
            TodayView(
                calendar: calendarViewModel,
                today: todayViewModel,
                assignments: assignmentsViewModel,
                onOpenModule: { moduleID, section, intent in
                    navigation.show(module: moduleID, section: section, intent: intent)
                },
                onShowCalendar: { navigation.showCalendar() },
                onCreateModule: { viewModel.editorMode = .create },
                onCreateLectureNote: { event in
                    guard let moduleID = event.moduleID else { return }
                    navigation.show(
                        module: moduleID,
                        section: .notes,
                        intent: .lectureNote(start: event.startDate, title: event.title)
                    )
                }
            )
        case .calendar:
            StudyCalendarView(viewModel: calendarViewModel, assignments: assignmentsViewModel) { moduleID, section in
                navigation.show(module: moduleID, section: section)
            }
        case .grades:
            GradesView(viewModel: viewModel) { moduleID in
                navigation.show(module: moduleID, section: .overview)
            }
        case .module(let id):
            if let module = viewModel.module(withID: id) {
                let live = calendarViewModel.currentLecture.flatMap { $0.moduleID == id ? $0 : nil }
                ModuleDetailView(
                    module: module,
                    section: sectionBinding(for: id),
                    pendingIntent: $navigation.pendingIntent,
                    upcomingEvents: calendarViewModel.upcomingEvents(forModule: id),
                    liveEvent: live,
                    liveProgress: live.map(calendarViewModel.progress(of:)) ?? 0,
                    referenceDate: calendarViewModel.referenceDate,
                    assignments: assignmentsViewModel,
                    makeSlidesViewModel: makeSlidesViewModel,
                    makeLearningViewModel: makeLearningViewModel,
                    onShowEvent: { event in
                        navigation.showCalendar()
                        calendarViewModel.reveal(event)
                    },
                    onEdit: { viewModel.editorMode = .edit(module) }
                )
                // Eigener Zustand pro Modul: geöffnetes PDF und Listen werden beim Moduswechsel zurückgesetzt.
                .id(module.id)
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        EmptyStateView(
            title: "Nichts ausgewählt",
            systemImage: "sidebar.left",
            message: "Wähle links „Heute“, den Kalender oder ein Modul, oder springe mit ⌘K direkt zu einem Ziel oder einer Notiz."
        )
        .background(Theme.background)
    }

    /// Löschen ist nur für bestehende Aufgaben möglich.
    private func deleteAction(for draft: AssignmentDraft) -> (() -> Void)? {
        guard let id = draft.assignmentID,
              let assignment = assignmentsViewModel.assignments.first(where: { $0.id == id }) else { return nil }
        return { assignmentsViewModel.delete(assignment) }
    }

    private func sectionBinding(for moduleID: UUID) -> Binding<ModuleSection> {
        Binding(
            get: { navigation.section(for: moduleID) },
            set: { navigation.show(module: moduleID, section: $0) }
        )
    }

    // MARK: Verlauf

    @ToolbarContentBuilder
    private var historyButtons: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { navigation.goBack() } label: {
                Label("Zurück", systemImage: "chevron.backward")
            }
            .disabled(!navigation.canGoBack)
            .help("Zurück (⌘[)")

            Button { navigation.goForward() } label: {
                Label("Vorwärts", systemImage: "chevron.forward")
            }
            .disabled(!navigation.canGoForward)
            .help("Vorwärts (⌘])")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { navigation.isQuickNavigatorPresented = true } label: {
                Label("Suchen", systemImage: "magnifyingglass")
            }
            .help("Gehe zu Modul oder Notiz (⌘K)")
        }
    }
}
