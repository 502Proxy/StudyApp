import SwiftUI

/// Controls of the study timer: phase, remaining time, module, start/pause, skip, reset and lengths.
struct StudyTimerPanel: View {
    @Bindable var viewModel: StudyTimerViewModel
    let modules: [StudyModule]

    private var tint: Color { viewModel.timer.phase.isBreak ? Theme.success : Theme.accent }

    var body: some View {
        VStack(spacing: 16) {
            Text(viewModel.timer.phase.title)
                .font(Theme.Typography.overline)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)

            ZStack {
                Circle().stroke(Theme.surfaceSecondary, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: viewModel.progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(viewModel.remainingText)
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 160, height: 160)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(viewModel.timer.phase.title), noch \(viewModel.remainingText)")

            Picker("Modul", selection: $viewModel.moduleID) {
                Text("Ohne Modul").tag(UUID?.none)
                ForEach(modules) { module in
                    Text(module.name).tag(UUID?.some(module.id))
                }
            }

            HStack {
                Button(primaryTitle) {
                    if viewModel.timer.isRunning {
                        viewModel.pause()
                    } else {
                        Task { await viewModel.start() }
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Überspringen") { viewModel.skip() }
                Button("Zurücksetzen") { viewModel.reset() }
                    .disabled(!viewModel.isActive && viewModel.timer.completedFocusPhases == 0)
            }

            DisclosureGroup("Dauer") {
                minutesStepper("Fokus", value: $viewModel.settings.focusMinutes)
                minutesStepper("Kurze Pause", value: $viewModel.settings.shortBreakMinutes)
                minutesStepper("Lange Pause", value: $viewModel.settings.longBreakMinutes)
            }
            .disabled(viewModel.isActive)

            let statistics = viewModel.statistics
            Text("Heute \(statistics.lastSevenDays.last?.minutes ?? 0) Min. · Serie \(statistics.streakDays) \(statistics.streakDays == 1 ? "Tag" : "Tage")")
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(20)
        .frame(width: 300)
        .task { viewModel.load() }
    }

    private var primaryTitle: String {
        if viewModel.timer.isRunning { return "Pause" }
        return viewModel.timer.isPaused ? "Weiter" : "Start"
    }

    private func minutesStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: StudyTimerSettings.minuteRange) {
            LabeledContent(title, value: "\(value.wrappedValue) Min.")
        }
    }
}

/// Toolbar button with the remaining time while the timer runs; opens the timer panel.
struct StudyTimerToolbarButton: View {
    let viewModel: StudyTimerViewModel
    let modules: [StudyModule]
    /// Module that is open, preselected when the timer is idle.
    let currentModuleID: UUID?
    @State private var isPresented = false

    var body: some View {
        Button {
            if !viewModel.isActive { viewModel.moduleID = currentModuleID }
            isPresented.toggle()
        } label: {
            if viewModel.isActive {
                Label(viewModel.remainingText, systemImage: viewModel.timer.isRunning ? "timer" : "pause.circle")
                    .labelStyle(.titleAndIcon)
                    .monospacedDigit()
            } else {
                Label("Lerntimer", systemImage: "timer")
            }
        }
        .help("Lerntimer")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            StudyTimerPanel(viewModel: viewModel, modules: modules)
        }
    }
}
