import SwiftUI

/// Exam countdowns with study plans: the module section „Klausur“ (`module` set) or the
/// sidebar overview „Klausuren“ across all modules (`module` nil).
struct ExamSectionView: View {
    @Bindable var viewModel: ExamsViewModel
    let module: StudyModule?

    var body: some View {
        let exams = module.map { viewModel.exams(forModule: $0.id) } ?? viewModel.upcoming
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if module == nil {
                    PageHeader("Klausuren", subtitle: exams.isEmpty ? nil : "\(exams.count) anstehend")
                }
                if exams.isEmpty {
                    emptyState
                } else {
                    ForEach(exams) { overview in
                        ExamPlanCard(overview: overview, viewModel: viewModel, showsModule: module == nil)
                    }
                    if let module {
                        Button {
                            viewModel.startNewExam(for: module)
                        } label: {
                            Label("Weiteren Termin eintragen …", systemImage: "plus")
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .padding(Theme.Spacing.page)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .task { viewModel.load() }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let module {
            EmptyStateView(
                title: "Kein Prüfungstermin",
                systemImage: "flag.checkered",
                message: "Klausurtermine aus deinem Stundenplan erscheinen hier automatisch. Du kannst einen Termin auch selbst eintragen.",
                actionTitle: "Termin eintragen …",
                action: { viewModel.startNewExam(for: module) }
            )
            .frame(minHeight: 320)
        } else {
            EmptyStateView(
                title: "Keine anstehenden Klausuren",
                systemImage: "flag.checkered",
                message: "Klausurtermine aus deinem Stundenplan erscheinen hier automatisch. Eigene Termine trägst du im Modul unter „Klausur“ ein."
            )
            .frame(minHeight: 320)
        }
    }
}

private struct ExamPlanCard: View {
    let overview: ExamOverview
    let viewModel: ExamsViewModel
    /// Shows the module above the title, for the overview across all modules.
    var showsModule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            SlimProgressBar(progress: overview.plan.progress, tint: overview.module.color.color)
            Text(paceText)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
            ForEach(overview.plan.days) { day in
                VStack(alignment: .leading, spacing: 6) {
                    Text(dayTitle(day.date))
                        .font(Theme.Typography.overline)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(day.items) { item in
                        PlanItemRow(item: item, isDone: false) { viewModel.toggle(item, of: overview.exam) }
                    }
                }
            }
            if !overview.plan.completed.isEmpty {
                DisclosureGroup("Erledigt (\(overview.plan.completed.count))") {
                    ForEach(overview.plan.completed) { item in
                        PlanItemRow(item: item, isDone: true) { viewModel.toggle(item, of: overview.exam) }
                    }
                }
                .font(Theme.Typography.caption)
            }
        }
        .card()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if showsModule {
                    HStack(spacing: 6) {
                        ModuleBadge(name: overview.module.name, color: overview.module.color, size: 16)
                        Text(overview.module.name)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Text(overview.exam.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                Text(details)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Pill(text: overview.countdown, systemImage: "flag.checkered", tint: overview.daysLeft <= 3 ? Theme.danger : Theme.accent)
            Menu {
                if overview.exam.isManual {
                    Button("Bearbeiten …") { viewModel.edit(overview.exam) }
                    Button("Löschen", role: .destructive) { viewModel.remove(overview.exam) }
                } else {
                    Button("Ausblenden") { viewModel.remove(overview.exam) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var details: String {
        var parts = [overview.exam.startDate.formatted(date: .complete, time: .shortened)]
        if !overview.exam.location.isEmpty { parts.append(overview.exam.location) }
        if !overview.exam.isManual { parts.append("aus dem Stundenplan") }
        return parts.joined(separator: " · ")
    }

    private var paceText: String {
        let open = overview.plan.openItemCount
        guard open > 0 else { return "Alles erledigt – viel Erfolg!" }
        let days = max(overview.plan.days.count, 1)
        let perDay = Double(open) / Double(days)
        return "\(overview.plan.completed.count) von \(overview.plan.totalCount) erledigt · noch \(open) in \(days) \(days == 1 ? "Tag" : "Tagen") (≈ \(String(format: "%.1f", perDay).replacingOccurrences(of: ".", with: ",")) pro Tag)"
    }

    private func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Heute" }
        if calendar.isDateInTomorrow(date) { return "Morgen" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

private struct PlanItemRow: View {
    let item: StudyPlanItem
    let isDone: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isDone ? Theme.success : Theme.textSecondary)
                Image(systemName: symbol)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 18)
                Text(item.title)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch item.kind {
        case .slides: "doc.richtext"
        case .flashcards: "rectangle.stack"
        case .finalReview: "checklist"
        }
    }
}

/// „Klausuren“ on the start page: every upcoming exam with countdown and progress.
struct UpcomingExamsCard: View {
    let exams: [ExamOverview]
    let onOpen: (ExamOverview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Klausuren", systemImage: "flag.checkered")
            ForEach(exams.prefix(5)) { overview in
                Button { onOpen(overview) } label: {
                    HStack(spacing: 12) {
                        ModuleBadge(name: overview.module.name, color: overview.module.color, size: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(overview.exam.title)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(overview.countdown)
                                    .font(Theme.Typography.caption.monospacedDigit())
                                    .foregroundStyle(overview.daysLeft <= 3 ? Theme.danger : Theme.textSecondary)
                            }
                            SlimProgressBar(progress: overview.plan.progress, tint: overview.module.color.color)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .card()
    }
}

/// Create or edit an exam entered by hand.
struct ExamEditorSheet: View {
    let onSave: (ExamDraft) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ExamDraft

    init(draft: ExamDraft, onSave: @escaping (ExamDraft) -> Bool) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.isNew ? "Prüfungstermin eintragen" : "Prüfung bearbeiten")
                .font(Theme.Typography.title)
                .padding([.horizontal, .top], 20)
            Form {
                TextField("Titel", text: $draft.title)
                DatePicker("Termin", selection: $draft.startDate, displayedComponents: [.date, .hourAndMinute])
                TextField("Raum (optional)", text: $draft.location)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    if onSave(draft) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmed.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 440)
        .background(Theme.surface)
    }
}
