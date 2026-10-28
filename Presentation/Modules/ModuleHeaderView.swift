import SwiftUI

/// Top of a module: name, code, ECTS and grade, the next exam, the four tabs and, for tabs with
/// several sections, a segmented control.
struct ModuleHeaderView: View {
    let module: StudyModule
    let isLive: Bool
    let nextExam: ExamOverview?
    @Binding var tab: ModuleTab
    @Binding var section: ModuleSection
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ModuleBadge(name: module.name, color: module.color, size: 46)
                titleAndDetails
                Spacer()
                if let nextExam {
                    examChip(nextExam)
                }
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Modul bearbeiten")
            }

            PillTabBar(
                items: ModuleTab.allCases,
                selection: $tab,
                title: \.title,
                systemImage: \.systemImage
            )

            if section.tab.sections.count > 1 {
                Picker("Bereich", selection: $section) {
                    ForEach(section.tab.sections) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    private var titleAndDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(module.name)
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if isLive {
                    LiveBadge()
                }
            }
            HStack(spacing: 6) {
                if !module.code.isEmpty {
                    Text(module.code)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let credits = module.credits {
                    Pill(text: "\(GradeScale.formatCredits(credits)) ECTS", tint: Theme.success)
                }
                if let grade = module.grade {
                    Pill(
                        text: "Note \(GradeScale.format(grade))",
                        tint: GradeScale.isPassing(grade) ? Theme.accent : Theme.danger
                    )
                }
            }
        }
    }

    /// Countdown to the next exam; opens its study plan.
    private func examChip(_ exam: ExamOverview) -> some View {
        Button { section = .exam } label: {
            Pill(
                text: "Klausur \(exam.countdown)",
                systemImage: "flag.checkered",
                tint: exam.daysLeft <= 3 ? Theme.danger : Theme.accent
            )
        }
        .buttonStyle(.plain)
        .help("Lernplan für die Klausur öffnen")
    }
}
