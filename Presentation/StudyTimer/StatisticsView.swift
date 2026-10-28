import Charts
import SwiftUI

/// „Statistik“: study time of the last days and this week, streak, time per module and study plan progress.
struct StatisticsView: View {
    let timer: StudyTimerViewModel
    let modules: [StudyModule]
    let exams: [ExamOverview]

    var body: some View {
        let statistics = timer.statistics
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                PageHeader("Statistik", subtitle: "Lernzeit aus dem Lerntimer")
                HStack(spacing: 14) {
                    MetricTile(title: "Heute", value: StudyTimerViewModel.durationText(statistics.lastSevenDays.last?.minutes ?? 0), systemImage: "sun.max")
                    MetricTile(title: "Diese Woche", value: StudyTimerViewModel.durationText(statistics.minutesThisWeek), systemImage: "calendar")
                    MetricTile(
                        title: "Serie",
                        value: statistics.streakDays == 1 ? "1 Tag" : "\(statistics.streakDays) Tage",
                        systemImage: "flame"
                    )
                }
                weekChart(statistics.lastSevenDays)
                if !statistics.modulesThisWeek.isEmpty {
                    modulesCard(statistics.modulesThisWeek)
                }
                if !exams.isEmpty {
                    studyPlansCard
                }
            }
            .padding(Theme.Spacing.page)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Statistik")
        .task { timer.load() }
    }

    private func weekChart(_ days: [StudyStatistics.Day]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Letzte 7 Tage", systemImage: "chart.bar")
            Chart(days, id: \.date) { day in
                BarMark(
                    x: .value("Tag", day.date, unit: .day),
                    y: .value("Minuten", day.minutes)
                )
                .foregroundStyle(Theme.accent)
                .cornerRadius(4)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                }
            }
            .chartYAxisLabel("Minuten")
            .frame(height: 180)
        }
        .card()
    }

    private func modulesCard(_ times: [StudyStatistics.ModuleTime]) -> some View {
        let maximum = max(times.map(\.minutes).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Module diese Woche", systemImage: "books.vertical")
            ForEach(times, id: \.moduleID) { time in
                let module = modules.first { $0.id == time.moduleID }
                HStack(spacing: 10) {
                    Circle()
                        .fill(module?.color.color ?? Theme.textTertiary)
                        .frame(width: 10, height: 10)
                    Text(module?.name ?? (time.moduleID == nil ? "Ohne Modul" : "Gelöschtes Modul"))
                        .lineLimit(1)
                        .frame(width: 200, alignment: .leading)
                    SlimProgressBar(progress: Double(time.minutes) / Double(maximum), tint: module?.color.color ?? Theme.accent)
                    Text(StudyTimerViewModel.durationText(time.minutes))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 70, alignment: .trailing)
                }
            }
        }
        .card()
    }

    private var studyPlansCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Lernpläne", systemImage: "flag.checkered")
            ForEach(exams) { overview in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(overview.module.name) · \(overview.exam.title)")
                            .lineLimit(1)
                        Spacer()
                        Text("\(overview.plan.completed.count) von \(overview.plan.totalCount) · \(overview.countdown)")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    SlimProgressBar(progress: overview.plan.progress, tint: overview.module.color.color)
                }
            }
        }
        .card()
    }
}

/// Small metric tile used on the statistics page.
private struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(Theme.Typography.metric)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
