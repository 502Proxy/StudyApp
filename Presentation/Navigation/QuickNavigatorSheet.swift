import SwiftUI

/// Schnellwechsler („Gehe zu …“, ⌘K): Tippen, mit Pfeiltasten wählen, Return öffnet.
struct QuickNavigatorSheet: View {
    let modules: [StudyModule]
    var notes: [NoteReference] = []
    let onSelect: (QuickNavigatorItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var highlightedID: QuickNavigatorItem.ID?
    @FocusState private var isSearchFocused: Bool

    private var results: [QuickNavigatorItem] {
        QuickNavigatorIndex.filter(QuickNavigatorIndex.items(modules: modules, notes: notes), query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Modul, Bereich oder Notizinhalt suchen …", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
            }
            .padding(16)
                .focused($isSearchFocused)
                .onSubmit(openHighlighted)
                .onKeyPress(.downArrow) { moveHighlight(by: 1); return .handled }
                .onKeyPress(.upArrow) { moveHighlight(by: -1); return .handled }
            Divider()
            resultList
        }
        .frame(width: 560, height: 420)
        .background(Theme.surface)
        .onExitCommand { dismiss() }
        .onAppear {
            highlightedID = results.first?.id
            isSearchFocused = true
        }
        .onChange(of: query) {
            highlightedID = results.first?.id
        }
    }

    @ViewBuilder
    private var resultList: some View {
        let items = results
        if items.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            row(for: item)
                                .id(item.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: highlightedID) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(for item: QuickNavigatorItem) -> some View {
        Button { open(item) } label: {
            HStack(spacing: 10) {
                Image(systemName: item.systemImage)
                    .foregroundStyle(item.moduleColor?.color ?? Theme.accent)
                    .frame(width: 22)
                Text(item.title)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.isNote {
                    Text("Notiz")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                highlightedID == item.id ? Theme.accent.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func moveHighlight(by offset: Int) {
        let items = results
        guard !items.isEmpty else { return }
        let current = items.firstIndex { $0.id == highlightedID } ?? 0
        let next = min(max(current + offset, 0), items.count - 1)
        highlightedID = items[next].id
    }

    private func openHighlighted() {
        guard let item = results.first(where: { $0.id == highlightedID }) ?? results.first else { return }
        open(item)
    }

    private func open(_ item: QuickNavigatorItem) {
        dismiss()
        onSelect(item)
    }
}
