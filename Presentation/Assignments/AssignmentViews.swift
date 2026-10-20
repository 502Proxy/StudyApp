import SwiftUI

extension AssignmentUrgency {
    var tint: Color {
        switch self {
        case .overdue: Theme.danger
        case .today: Theme.warning
        case .soon: Theme.accent
        case .later: Theme.textSecondary
        case .done: Theme.success
        }
    }
}

/// Eine Aufgabe mit Abhak-Kreis, Fälligkeit und optional dem Modul.
struct AssignmentRow: View {
    let assignment: Assignment
    let urgency: AssignmentUrgency
    let dueText: String
    var module: StudyModule?
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: assignment.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(assignment.isCompleted ? Theme.success : urgency.tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(assignment.isCompleted ? "Als offen markieren" : "Als erledigt markieren")
            .accessibilityLabel(assignment.isCompleted ? "Erledigt" : "Offen")

            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(assignment.isCompleted ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(assignment.isCompleted, color: Theme.textTertiary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let module {
                        ModuleBadge(name: module.name, color: module.color, size: 16)
                        Text(module.name)
                            .lineLimit(1)
                        Text("·")
                    }
                    Label(dueText, systemImage: urgency == .overdue ? "exclamationmark.circle" : "clock")
                        .foregroundStyle(assignment.isCompleted ? Theme.textTertiary : urgency.tint)
                        .lineLimit(1)
                }
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
                if !assignment.details.isEmpty, !assignment.isCompleted {
                    Text(assignment.details)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button(assignment.isCompleted ? "Als offen markieren" : "Als erledigt markieren", action: onToggle)
            Button("Bearbeiten …", action: onEdit)
            Divider()
            Button("Löschen", role: .destructive, action: onDelete)
        }
    }
}

/// Bereich „Aufgaben“ eines Moduls.
struct AssignmentsView: View {
    @Bindable var viewModel: AssignmentsViewModel
    let module: StudyModule
    @State private var showsCompleted = false

    private var all: [Assignment] { viewModel.assignments(forModule: module.id) }
    private var open: [Assignment] { all.filter { !$0.isCompleted } }
    private var completed: [Assignment] { all.filter(\.isCompleted) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader("Aufgaben & Abgaben", subtitle: subtitle) {
                Button {
                    viewModel.startNewAssignment(moduleID: module.id)
                } label: {
                    Label("Neue Aufgabe", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .help("Neue Aufgabe (⌥⌘T)")
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, 14)
            Divider()

            if all.isEmpty {
                EmptyStateView(
                    title: "Keine Aufgaben",
                    systemImage: "checklist",
                    message: "Trage Übungsblätter, Hausarbeiten oder Referate mit Abgabedatum ein. Sie erscheinen auf „Heute“ und im Kalender.",
                    actionTitle: "Erste Aufgabe anlegen",
                    action: { viewModel.startNewAssignment(moduleID: module.id) }
                )
            } else {
                List {
                    Section {
                        if open.isEmpty {
                            Label("Alles erledigt", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.success)
                                .padding(.vertical, 6)
                        }
                        ForEach(open) { assignment in
                            row(assignment)
                        }
                    } header: {
                        Text("Offen (\(open.count))")
                    }

                    if !completed.isEmpty {
                        Section(isExpanded: $showsCompleted) {
                            ForEach(completed) { assignment in
                                row(assignment)
                            }
                        } header: {
                            Text("Erledigt (\(completed.count))")
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .task { viewModel.load() }
    }

    private var subtitle: String {
        let overdue = open.filter { viewModel.urgency(of: $0) == .overdue }.count
        var parts = ["\(open.count) offen"]
        if overdue > 0 { parts.append("\(overdue) überfällig") }
        return parts.joined(separator: " · ")
    }

    private func row(_ assignment: Assignment) -> some View {
        AssignmentRow(
            assignment: assignment,
            urgency: viewModel.urgency(of: assignment),
            dueText: viewModel.dueText(for: assignment),
            onToggle: { viewModel.setCompleted(assignment, !assignment.isCompleted) },
            onEdit: { viewModel.edit(assignment) },
            onDelete: { viewModel.delete(assignment) }
        )
    }
}

/// Anlegen und Bearbeiten einer Aufgabe.
struct AssignmentEditorSheet: View {
    let modules: [StudyModule]
    let onSave: (AssignmentDraft) -> Bool
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AssignmentDraft
    @FocusState private var isTitleFocused: Bool

    init(draft: AssignmentDraft, modules: [StudyModule], onSave: @escaping (AssignmentDraft) -> Bool, onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: draft)
        self.modules = modules
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && draft.moduleID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.isNew ? "Neue Aufgabe" : "Aufgabe bearbeiten")
                .font(Theme.Typography.title)
                .padding([.horizontal, .top], 20)

            Form {
                TextField("Titel", text: $draft.title, prompt: Text("z. B. Übungsblatt 3"))
                    .focused($isTitleFocused)
                Picker("Modul", selection: $draft.moduleID) {
                    if draft.moduleID == nil {
                        Text("Modul wählen").tag(UUID?.none)
                    }
                    ForEach(modules) { module in
                        Text(module.name).tag(UUID?.some(module.id))
                    }
                }
                DatePicker("Fällig am", selection: $draft.dueDate, displayedComponents: [.date, .hourAndMinute])
                HStack(spacing: 6) {
                    ForEach(QuickDue.allCases) { quick in
                        Button(quick.title) { draft.dueDate = quick.date(from: Date()) }
                            .controlSize(.small)
                    }
                }
                Section("Details (optional)") {
                    TextEditor(text: $draft.details)
                        .frame(minHeight: 70)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                if let onDelete, !draft.isNew {
                    Button("Löschen", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    if onSave(draft) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 480)
        .background(Theme.surface)
        .onAppear { isTitleFocused = draft.isNew }
    }
}

/// Schnellwahl für typische Abgabetermine.
private enum QuickDue: String, CaseIterable, Identifiable {
    case tomorrow
    case nextWeek
    case twoWeeks

    var id: Self { self }

    var title: String {
        switch self {
        case .tomorrow: "Morgen"
        case .nextWeek: "In 1 Woche"
        case .twoWeeks: "In 2 Wochen"
        }
    }

    func date(from now: Date, calendar: Calendar = .current) -> Date {
        let days = switch self {
        case .tomorrow: 1
        case .nextWeek: 7
        case .twoWeeks: 14
        }
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}
