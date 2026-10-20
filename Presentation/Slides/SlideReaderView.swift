import AppKit
import SwiftUI
internal import PDFKit

/// PDF-Viewer mit Werkzeugleiste: Seitenwechsel, Zoom, Markierungswerkzeuge, Seiten- oder
/// Markierungsübersicht und einer ein- und ausblendbaren Notizen-Seitenleiste.
struct SlideReaderView: View {
    let document: SlideDocument
    let fileURL: URL
    /// Seite (1-basiert), auf die beim Öffnen bzw. bei einer neuen Anfrage gesprungen wird.
    var requestedPage: Int?
    var pageRequestID = UUID()
    let makeNotesViewModel: () -> NotesViewModel
    /// Schreibt das PDF nach dem Markieren zurück.
    let saveDocument: (Data) throws -> Void
    var onPageChange: (Int) -> Void = { _ in }
    let onClose: () -> Void

    private enum SidebarMode: String, CaseIterable, Identifiable {
        case pages = "Seiten"
        case annotations = "Markierungen"
        case search = "Suche"
        var id: Self { self }

        var systemImage: String {
            switch self {
            case .pages: "square.grid.2x2"
            case .annotations: "highlighter"
            case .search: "magnifyingglass"
            }
        }
    }

    // Der Controller entsteht erst beim Erscheinen, damit das PDF nicht bei jedem
    // Neuaufbau der übergeordneten View erneut geladen wird. Gleiches gilt für die Notizen.
    @State private var controller: PDFReaderController?
    @State private var notes: NotesViewModel?
    @State private var showsSidebar = true
    @State private var sidebarMode: SidebarMode = .pages
    @State private var pendingText = ""
    @State private var isSearching = false
    @State private var searchQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isSearchFieldFocused: Bool
    @AppStorage(ViewPreferences.slideReaderShowsNotesKey) private var showsNotes = true

    var body: some View {
        Group {
            if let controller {
                content(controller)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .task {
            if controller == nil {
                controller = PDFReaderController(fileURL: fileURL, save: saveDocument)
                await jumpToRequestedPage()
            }
            if notes == nil {
                let viewModel = makeNotesViewModel()
                viewModel.load()
                notes = viewModel
            }
        }
        .onChange(of: pageRequestID) { _, _ in
            Task { await jumpToRequestedPage() }
        }
        .onChange(of: controller?.pageIndex) { _, index in
            if let index { onPageChange(index + 1) }
        }
        .onDisappear { controller?.saveNow() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            controller?.saveNow()
        }
    }

    /// Die PDFView braucht nach dem Einhängen einen Layout-Durchlauf, bevor sie zuverlässig springt.
    private func jumpToRequestedPage() async {
        guard let page = requestedPage, page > 1, let controller else { return }
        try? await Task.sleep(for: .milliseconds(120))
        controller.goToPage(number: page)
    }

    @ViewBuilder
    private func content(_ controller: PDFReaderController) -> some View {
        if controller.isLoaded {
            VStack(spacing: 0) {
                toolbar(controller)
                Divider()
                if isSearching {
                    searchBar(controller)
                    Divider()
                }
                AnnotationToolbar(controller: controller, onQuote: { quoteSelection(from: controller) }, canQuote: notes != nil)
                Divider()
                HSplitView {
                    HStack(spacing: 0) {
                        if showsSidebar {
                            sidebar(controller)
                                .frame(width: 172)
                            Divider()
                        }
                        PDFKitView(pdfView: controller.pdfView)
                            .frame(minWidth: 340)
                    }
                    // Das PDF bekommt beim Teilen den Vorrang vor den Notizen.
                    .layoutPriority(1)

                    if showsNotes, let notes {
                        NoteEditorView(
                            viewModel: notes,
                            currentPageNumber: controller.pageIndex + 1,
                            onSelectNote: { note in
                                if let pageNumber = note.pageNumber {
                                    controller.goToPage(number: pageNumber)
                                }
                            }
                        )
                        .frame(minWidth: 320, idealWidth: 380, maxWidth: 560)
                    }
                }
            }
            .errorAlert(message: controller.errorMessage) { controller.errorMessage = nil }
            .sheet(item: Bindable(controller).pendingTextLocation) { location in
                TextAnnotationSheet(text: $pendingText) {
                    controller.addText(pendingText, at: location)
                    pendingText = ""
                } onCancel: {
                    controller.pendingTextLocation = nil
                    pendingText = ""
                }
            }
        } else {
            VStack(spacing: 0) {
                HStack {
                    backButton
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                Divider()
                ContentUnavailableView(
                    "PDF nicht lesbar",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Die Datei „\(document.title)“ konnte nicht geöffnet werden.")
                )
            }
        }
    }

    /// Übernimmt die Textauswahl als Zitat in die Notiz und blendet die Notizen ein.
    private func quoteSelection(from controller: PDFReaderController) {
        guard let text = controller.selectedText, let notes else { return }
        showsNotes = true
        notes.appendQuote(text, fromPage: controller.pageIndex + 1)
        controller.pdfView.clearSelection()
    }

    // MARK: Suche

    private func openSearch() {
        isSearching = true
        showsSidebar = true
        sidebarMode = .search
        isSearchFieldFocused = true
    }

    private func closeSearch(_ controller: PDFReaderController) {
        searchTask?.cancel()
        isSearching = false
        searchQuery = ""
        controller.clearSearch()
        if sidebarMode == .search { sidebarMode = .pages }
    }

    private func searchBar(_ controller: PDFReaderController) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textTertiary)
                TextField("Im PDF suchen", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .focused($isSearchFieldFocused)
                    .onSubmit { controller.nextSearchResult() }
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.shift) else { return .ignored }
                        controller.previousSearchResult()
                        return .handled
                    }
                    .onExitCommand { closeSearch(controller) }
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .frame(maxWidth: 360)

            Text(searchStatus(controller))
                .font(Theme.Typography.small.monospacedDigit())
                .foregroundStyle(controller.searchResults.isEmpty && !controller.searchedText.isEmpty ? Theme.danger : Theme.textSecondary)

            Button { controller.previousSearchResult() } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(controller.searchResults.isEmpty)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .help("Vorheriger Treffer (⇧↩ oder ⇧⌘G)")

            Button { controller.nextSearchResult() } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(controller.searchResults.isEmpty)
            .keyboardShortcut("g", modifiers: .command)
            .help("Nächster Treffer (↩ oder ⌘G)")

            Spacer()

            Button("Fertig") { closeSearch(controller) }
                .help("Suche schließen (esc)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Theme.surface)
        .onChange(of: searchQuery) { _, query in
            // Kurz warten, damit nicht bei jedem Tastendruck das ganze PDF durchsucht wird.
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                controller.search(query)
            }
        }
    }

    private func searchStatus(_ controller: PDFReaderController) -> String {
        if controller.searchedText.isEmpty { return "" }
        if controller.searchResults.isEmpty { return "Keine Treffer" }
        let current = (controller.currentSearchIndex ?? 0) + 1
        return "\(current) von \(controller.searchResults.count)"
    }

    // MARK: Seitenleiste

    @ViewBuilder
    private func sidebar(_ controller: PDFReaderController) -> some View {
        VStack(spacing: 0) {
            // Symbole statt Text: „Markierungen“ passt in die schmale Leiste nicht hinein.
            Picker("Seitenleiste", selection: $sidebarMode) {
                ForEach(SidebarMode.allCases) { mode in
                    Image(systemName: mode.systemImage)
                        .help(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Text(sidebarMode.rawValue)
                .font(Theme.Typography.overline)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            Divider()
            switch sidebarMode {
            case .pages:
                PDFThumbnailStrip(pdfView: controller.pdfView)
            case .annotations:
                AnnotationListView(controller: controller)
            case .search:
                SearchResultsListView(controller: controller)
            }
        }
        .background(Theme.surfaceSecondary)
    }

    // MARK: Werkzeugleiste

    private var backButton: some View {
        Button(action: onClose) {
            Label("Alle Folien", systemImage: "chevron.left")
                .font(Theme.Typography.small.weight(.medium))
        }
        .buttonStyle(.borderless)
        .help("Zurück zur Folienliste")
    }

    private func toolbar(_ controller: PDFReaderController) -> some View {
        HStack(spacing: 14) {
            backButton

            Text(document.title)
                .font(Theme.Typography.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 6) {
                Button { controller.goToPreviousPage() } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(controller.pageIndex <= 0)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .help("Vorherige Seite (⌥⌘↑)")

                Text("\(controller.pageIndex + 1) / \(controller.pageCount)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.surfaceSecondary, in: Capsule())

                Button { controller.goToNextPage() } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(controller.pageIndex >= controller.pageCount - 1)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .help("Nächste Seite (⌥⌘↓)")
            }

            Divider().frame(height: 16)

            HStack(spacing: 8) {
                Button { controller.zoomOut() } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Verkleinern")

                Button { controller.zoomIn() } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Vergrößern")

                Button { controller.zoomToFit() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .help("An Fenster anpassen")
            }

            Divider().frame(height: 16)

            Button {
                openSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(isSearching ? Theme.accent : Theme.textPrimary)
            }
            .keyboardShortcut("f", modifiers: .command)
            .help("Im PDF suchen (⌘F)")

            // Zusätzlich ⌃F, für alle, die das von Windows gewohnt sind.
            Button("Im PDF suchen", action: openSearch)
                .keyboardShortcut("f", modifiers: .control)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)

            Button {
                showsSidebar.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Seiten und Markierungen ein- oder ausblenden")

            Button {
                showsNotes.toggle()
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundStyle(showsNotes ? Theme.accent : Theme.textPrimary)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .help("Notizen ein- oder ausblenden (⌥⌘N)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }
}

// MARK: - Markierungswerkzeuge

/// Zweite Leiste: Werkzeug, Farbe, Strichstärke und Aktionen für die Auswahl.
private struct AnnotationToolbar: View {
    @Bindable var controller: PDFReaderController
    let onQuote: () -> Void
    let canQuote: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button {
                        controller.select(tool)
                    } label: {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 30, height: 26)
                            .foregroundStyle(controller.tool == tool ? Theme.accent : Theme.textSecondary)
                            .background(
                                controller.tool == tool ? Theme.accentSoft : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(tool.title)
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(controller.tool == tool ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            if controller.tool.usesColor {
                HStack(spacing: 6) {
                    ForEach(AnnotationColor.allCases) { color in
                        Button {
                            controller.color = color
                        } label: {
                            Circle()
                                .fill(color.color)
                                .frame(width: 16, height: 16)
                                .overlay {
                                    if controller.color == color {
                                        Circle().strokeBorder(Theme.textPrimary, lineWidth: 2).padding(-3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(color.label)
                        .accessibilityLabel(color.label)
                    }
                }
            }

            if controller.tool == .pen {
                Picker("Strichstärke", selection: $controller.penWidth) {
                    ForEach(PenWidth.allCases) { width in
                        Text(width.label).tag(width)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            Spacer(minLength: 8)

            Text(hint)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)

            Button {
                onQuote()
            } label: {
                Label("In Notiz", systemImage: "text.quote")
            }
            .disabled(!controller.hasSelection || !canQuote)
            .help("Markierten Text als Zitat in die Notiz übernehmen (⇧⌘E)")
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button {
                controller.applyMarkupToSelection(using: .highlight)
            } label: {
                Image(systemName: "highlighter")
            }
            .disabled(!controller.hasSelection)
            .keyboardShortcut("h", modifiers: [.command, .shift])
            .help("Auswahl markieren (⇧⌘H)")

            Button {
                controller.removeMarkupInSelection()
            } label: {
                Image(systemName: "eraser.line.dashed")
            }
            .disabled(!controller.hasSelection)
            .help("Markierungen in der Auswahl entfernen")

            Button {
                controller.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!controller.canUndo)
            .help("Letzte Markierung rückgängig machen")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Theme.surface)
    }

    private var hint: String {
        switch controller.tool {
        case .select: "Text auswählen, um ihn zu kopieren oder zu übernehmen"
        case .highlight, .underline, .strikeOut: "Text auswählen – wird sofort markiert"
        case .pen: "Mit gedrückter Maustaste zeichnen"
        case .text: "Auf die Folie klicken, um ein Textfeld zu setzen"
        case .eraser: "Markierung, Zeichnung oder Textfeld anklicken"
        }
    }
}

/// Liste aller Markierungen im Dokument; ein Klick springt an die Stelle.
private struct AnnotationListView: View {
    let controller: PDFReaderController

    var body: some View {
        // Das Lesen von `annotationRevision` sorgt dafür, dass die Liste nach jeder Änderung neu berechnet wird.
        let _ = controller.annotationRevision
        let summaries = controller.annotationSummaries()
        if summaries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "highlighter")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textTertiary)
                Text("Noch keine Markierungen")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(summaries) { summary in
                        Button {
                            controller.reveal(summary)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(summary.color)
                                    .frame(width: 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("Seite \(summary.pageNumber)", systemImage: summary.tool.systemImage)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(Theme.textSecondary)
                                    Text(summary.text)
                                        .font(Theme.Typography.small)
                                        .foregroundStyle(Theme.textPrimary)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }
}

/// Eingabe für ein Textfeld auf der Folie.
private struct TextAnnotationSheet: View {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Textfeld")
                .font(Theme.Typography.title)
            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(width: 340, height: 110)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .focused($isFocused)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Hinzufügen", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .background(Theme.surface)
        .onAppear { isFocused = true }
    }
}

/// Trefferliste der PDF-Suche mit Seite und Textausschnitt.
private struct SearchResultsListView: View {
    let controller: PDFReaderController

    var body: some View {
        if controller.searchedText.isEmpty {
            hint("Suchbegriff oben eingeben (⌘F)", systemImage: "magnifyingglass")
        } else if controller.searchResults.isEmpty {
            hint("Keine Treffer für „\(controller.searchedText)“", systemImage: "text.magnifyingglass")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(controller.searchResults) { result in
                            let isCurrent = controller.currentSearchIndex == result.id
                            Button {
                                controller.showSearchResult(at: result.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Seite \(result.pageNumber)")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(isCurrent ? Theme.accent : Theme.textSecondary)
                                    highlighted(result.context)
                                        .font(Theme.Typography.small)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(isCurrent ? Theme.accentSoft : Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(result.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: controller.currentSearchIndex) { _, index in
                    if let index { withAnimation { proxy.scrollTo(index, anchor: .center) } }
                }
            }
        }
    }

    /// Hebt den Suchbegriff im Ausschnitt fett hervor.
    private func highlighted(_ context: String) -> Text {
        var attributed = AttributedString(context)
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: controller.searchedText, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].font = .system(size: 11, weight: .bold)
            attributed[range].foregroundColor = Theme.textPrimary
            searchRange = range.upperBound..<attributed.endIndex
        }
        return Text(attributed).foregroundStyle(Theme.textSecondary)
    }

    private func hint(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
