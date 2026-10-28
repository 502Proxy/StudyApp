import SwiftUI

/// Verwaltung der Kalenderquellen: Feed abonnieren, Datei importieren, aktualisieren, entfernen.
struct CalendarSourcesSheet: View {
    @Bindable var viewModel: StudyCalendarViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var formError: String?
    @State private var isSubscribing = false
    @State private var isImporting = false
    @State private var pendingRemoval: CalendarSource?
    @FocusState private var isAddressFocused: Bool

    private var canSubscribe: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSubscribing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Kalenderquellen")
                .font(Theme.Typography.title)

            addSection
            Divider()
            sourceList

            HStack {
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .frame(minHeight: 420)
        .background(Theme.surface)
        .calendarFileImporter(isPresented: $isImporting, viewModel: viewModel)
        .onAppear { isAddressFocused = true }
        .confirmationDialog(
            "Quelle entfernen?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { source in
            Button("„\(source.name)“ entfernen", role: .destructive) { viewModel.deleteSource(source) }
        } message: { _ in
            Text("Die Quelle und alle daraus importierten Termine werden gelöscht.")
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hinzufügen").font(.headline)
            HStack {
                TextField("https://…/kalender.ics oder webcal://…", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .focused($isAddressFocused)
                    .onSubmit(subscribe)
                Button(action: subscribe) {
                    if isSubscribing {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Abonnieren")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubscribe)
            }
            if let formError {
                Label(formError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button { isImporting = true } label: {
                    Label(".ics-Datei importieren …", systemImage: "square.and.arrow.down")
                }
                Spacer()
            }
            Text("Abonnements werden beim Hinzufügen, beim App-Start und danach stündlich abgeglichen. Wiederkehrende Termine werden vollständig übernommen; Lehrveranstaltungen werden automatisch zu Modulen.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Label {
                Text("**Stud.IP:** Unter „Planer → Stundenplan“ bzw. „Termine“ findest du „Exportieren“ bzw. „Abonnieren“. Kopiere den dort angezeigten Link und füge ihn oben ein – Raumänderungen und Ausfälle kommen dann automatisch an.")
            } icon: {
                Image(systemName: "graduationcap")
            }
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var sourceList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eingerichtete Quellen").font(.headline)
            if viewModel.sources.isEmpty {
                Text("Noch keine Kalenderquellen.")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.sources) { source in
                            sourceRow(source)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private static func symbol(for kind: CalendarSourceKind) -> String {
        switch kind {
        case .file: "doc.text"
        case .subscription: "link"
        case .studIP: "building.columns"
        }
    }

    private func sourceRow(_ source: CalendarSource) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(for: source.kind))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.callout.weight(.medium)).lineLimit(1)
                Text(detail(for: source))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if source.kind == .subscription {
                Button {
                    Task { await viewModel.refresh(source) }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isSyncing)
                .help("Abonnement aktualisieren")
            }
            Button(role: .destructive) {
                pendingRemoval = source
            } label: {
                Label("Entfernen", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Quelle und importierte Termine entfernen")
        }
        .padding(10)
        .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detail(for source: CalendarSource) -> String {
        var parts = [StudyCalendarViewModel.eventCountText(viewModel.eventCount(for: source))]
        if let date = source.lastSyncedAt {
            parts.append("Stand \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private func subscribe() {
        guard canSubscribe else { return }
        formError = nil
        isSubscribing = true
        Task {
            do {
                try await viewModel.subscribe(to: address)
                address = ""
            } catch {
                formError = error.localizedDescription
            }
            isSubscribing = false
        }
    }
}
