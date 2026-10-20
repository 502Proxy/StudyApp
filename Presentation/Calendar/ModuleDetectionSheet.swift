import SwiftUI

/// Übersicht der im Kalender erkannten Lehrveranstaltungen. Ausgewählte werden als Modul angelegt
/// (bzw. mit dem bestehenden Modul verknüpft), alle ihre Termine erhalten die Modulzuordnung.
struct ModuleDetectionSheet: View {
    let viewModel: StudyCalendarViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [ModuleCandidate] = []
    @State private var selectedKeys: Set<String> = []
    @State private var showsAll = false

    private var visibleCandidates: [ModuleCandidate] {
        showsAll ? candidates : candidates.filter { $0.isLikelyCourse || $0.existingModuleID != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Module aus dem Kalender")
                    .font(Theme.Typography.title)
                Text("StudyApp fasst Vorlesung, Übung und Tutorium desselben Fachs zusammen. Ausgewählte Veranstaltungen werden als Modul angelegt und alle zugehörigen Termine verknüpft.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)

            Divider()

            if visibleCandidates.isEmpty {
                EmptyStateView(
                    title: "Keine Veranstaltungen erkannt",
                    systemImage: "wand.and.stars",
                    message: "Im Kalender wurden keine wiederkehrenden Lehrveranstaltungen gefunden."
                )
                .frame(minHeight: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach($candidates) { $candidate in
                            if showsAll || candidate.isLikelyCourse || candidate.existingModuleID != nil {
                                CandidateRow(
                                    candidate: $candidate,
                                    existingModule: candidate.existingModuleID.flatMap { id in viewModel.modules.first { $0.id == id } },
                                    isSelected: Binding(
                                        get: { selectedKeys.contains(candidate.key) },
                                        set: { isOn in
                                            if isOn { selectedKeys.insert(candidate.key) } else { selectedKeys.remove(candidate.key) }
                                        }
                                    )
                                )
                            }
                        }
                    }
                    .padding(16)
                }
                .frame(minHeight: 300, maxHeight: 460)
                .background(Theme.background)
            }

            Divider()

            HStack {
                Toggle("Auch einzelne Termine zeigen", isOn: $showsAll)
                    .toggleStyle(.checkbox)
                    .font(Theme.Typography.small)
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(selectedKeys.isEmpty ? "Übernehmen" : "\(selectedKeys.count) übernehmen") {
                    apply()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(selectedKeys.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 620)
        .background(Theme.surface)
        .onAppear(perform: prepare)
    }

    private func prepare() {
        candidates = viewModel.moduleCandidates()
        let ignored = viewModel.ignoredCourseKeys
        // Vorausgewählt: aktuelle Veranstaltungen, die nicht abgelehnt wurden und noch etwas zu tun haben.
        selectedKeys = Set(candidates.filter { candidate in
            guard !ignored.contains(candidate.key) else { return false }
            if candidate.existingModuleID != nil { return !candidate.unlinkedEventIDs.isEmpty }
            return candidate.isLikelyCourse && candidate.isCurrent
        }.map(\.key))
    }

    private func apply() {
        let selected = candidates.filter { selectedKeys.contains($0.key) }
        let rejected = visibleCandidates.filter { !selectedKeys.contains($0.key) && $0.isLikelyCourse }
        viewModel.applyModuleCandidates(selected, rejected: rejected)
    }
}

private struct CandidateRow: View {
    @Binding var candidate: ModuleCandidate
    let existingModule: StudyModule?
    @Binding var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("Übernehmen", isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                if let existingModule {
                    HStack(spacing: 8) {
                        ModuleBadge(name: existingModule.name, color: existingModule.color, size: 22)
                        Text(existingModule.name)
                            .font(Theme.Typography.headline)
                        Pill(text: "bestehendes Modul", tint: Theme.success)
                    }
                } else {
                    HStack(spacing: 8) {
                        TextField("Name", text: $candidate.name)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.Typography.headline)
                        TextField("Kürzel", text: $candidate.code)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(candidate.kinds, id: \.self) { kind in
                        Pill(text: kind.label, tint: Theme.accent)
                    }
                    Text(details)
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous)
                .strokeBorder(isSelected ? Theme.accent.opacity(0.5) : Theme.surfaceBorder)
        }
        .opacity(candidate.isCurrent ? 1 : 0.7)
    }

    private var details: String {
        var parts = [StudyCalendarViewModel.eventCountText(candidate.occurrenceCount)]
        let first = candidate.firstStart.formatted(.dateTime.day().month(.abbreviated))
        let last = candidate.lastStart.formatted(.dateTime.day().month(.abbreviated).year())
        parts.append(candidate.occurrenceCount > 1 ? "\(first) – \(last)" : last)
        if existingModule != nil, !candidate.unlinkedEventIDs.isEmpty {
            parts.append("\(candidate.unlinkedEventIDs.count) noch nicht verknüpft")
        }
        if !candidate.isCurrent { parts.append("früheres Semester") }
        return parts.joined(separator: " · ")
    }
}
