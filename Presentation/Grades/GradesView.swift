import SwiftUI

/// Notenübersicht: gewichteter Schnitt, Leistungspunkte und je Modul Note und ECTS zum direkten Bearbeiten.
struct GradesView: View {
    @Bindable var viewModel: ModulesViewModel
    let onOpenModule: (UUID) -> Void

    var body: some View {
        let summary = viewModel.gradeSummary
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                PageHeader("Noten & ECTS", subtitle: "Gewichtet nach Leistungspunkten · bestanden bis 4,0")

                HStack(spacing: 14) {
                    metric(
                        title: "Notenschnitt",
                        value: summary.weightedAverage.map(GradeScale.format) ?? "–",
                        detail: summary.gradedModuleCount == 0 ? "Noch keine Noten" : "aus \(summary.gradedModuleCount - summary.failedModuleCount) bestandenen Modulen",
                        systemImage: "graduationcap",
                        tint: Theme.accent
                    )
                    creditsMetric(summary)
                    metric(
                        title: "Offene Module",
                        value: "\(viewModel.modules.count - summary.gradedModuleCount)",
                        detail: summary.failedModuleCount > 0 ? "\(summary.failedModuleCount) nicht bestanden" : "ohne Note",
                        systemImage: "hourglass",
                        tint: summary.failedModuleCount > 0 ? Theme.danger : Theme.warning
                    )
                }

                if viewModel.modules.isEmpty {
                    EmptyStateView(
                        title: "Noch keine Module",
                        systemImage: "graduationcap",
                        message: "Lege Module an oder importiere deinen Stundenplan. Danach kannst du hier Noten und Leistungspunkte eintragen."
                    )
                    .frame(minHeight: 260)
                } else {
                    VStack(spacing: 0) {
                        header
                        ForEach(viewModel.modules) { module in
                            Divider()
                            GradeRow(module: module, viewModel: viewModel, onOpen: { onOpenModule(module.id) })
                                .id("\(module.id)-\(module.credits ?? -1)-\(module.grade ?? -1)")
                        }
                    }
                    .card(padding: 0)

                    Text("Tipp: Werte mit Komma oder Punkt eingeben und mit ↩ bestätigen. Ein leeres Feld entfernt den Wert. Module mit 5,0 zählen nicht zum Schnitt und nicht zu den erreichten ECTS.")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(Theme.Spacing.page)
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Noten & ECTS")
    }

    private var header: some View {
        HStack {
            Text("Modul").frame(maxWidth: .infinity, alignment: .leading)
            Text("ECTS").frame(width: 80, alignment: .leading)
            Text("Note").frame(width: 80, alignment: .leading)
            Text("Status").frame(width: 130, alignment: .leading)
        }
        .font(Theme.Typography.overline)
        .textCase(.uppercase)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func metric(title: String, value: String, detail: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.headline)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func creditsMetric(_ summary: GradeSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Leistungspunkte", systemImage: "rosette")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.success)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(GradeScale.formatCredits(summary.earnedCredits))
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                Text("/ \(GradeScale.formatCredits(summary.plannedCredits)) ECTS")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            SlimProgressBar(
                progress: summary.plannedCredits > 0 ? summary.earnedCredits / summary.plannedCredits : 0,
                tint: Theme.success
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct GradeRow: View {
    let module: StudyModule
    let viewModel: ModulesViewModel
    let onOpen: () -> Void

    @State private var creditsText: String
    @State private var gradeText: String
    @FocusState private var focusedField: Field?

    private enum Field { case credits, grade }

    init(module: StudyModule, viewModel: ModulesViewModel, onOpen: @escaping () -> Void) {
        self.module = module
        self.viewModel = viewModel
        self.onOpen = onOpen
        _creditsText = State(initialValue: module.credits.map(GradeScale.formatCredits) ?? "")
        _gradeText = State(initialValue: module.grade.map(GradeScale.format) ?? "")
    }

    var body: some View {
        HStack {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    ModuleBadge(name: module.name, color: module.color, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(module.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if !module.code.isEmpty {
                            Text(module.code)
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("Modul öffnen")

            TextField("–", text: $creditsText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .focused($focusedField, equals: .credits)
                .onSubmit(commit)
                .padding(.trailing, 16)

            TextField("–", text: $gradeText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .focused($focusedField, equals: .grade)
                .onSubmit(commit)
                .padding(.trailing, 16)

            status
                .frame(width: 130, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .onChange(of: focusedField) { old, new in
            // Beim Verlassen eines Feldes speichern, auch ohne ↩.
            if old != nil, new == nil { commit() }
        }
    }

    @ViewBuilder
    private var status: some View {
        if let grade = module.grade {
            if GradeScale.isPassing(grade) {
                Pill(text: "Bestanden", systemImage: "checkmark", tint: Theme.success)
            } else {
                Pill(text: "Nicht bestanden", systemImage: "xmark", tint: Theme.danger)
            }
        } else {
            Pill(text: "Offen", tint: Theme.textSecondary)
        }
    }

    private func commit() {
        let currentCredits = module.credits.map(GradeScale.formatCredits) ?? ""
        let currentGrade = module.grade.map(GradeScale.format) ?? ""
        guard creditsText.trimmed != currentCredits || gradeText.trimmed != currentGrade else { return }
        if !viewModel.updateGrade(of: module, creditsText: creditsText, gradeText: gradeText) {
            // Ungültige Eingabe: auf den gespeicherten Wert zurücksetzen, die Meldung zeigt RootView.
            creditsText = currentCredits
            gradeText = currentGrade
        }
    }
}
