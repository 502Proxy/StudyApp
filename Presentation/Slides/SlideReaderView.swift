import AppKit
import SwiftUI

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
        var id: Self { self }
    }

    // Der Controller entsteht erst beim Erscheinen, damit das PDF nicht bei jedem
    // Neuaufbau der übergeordneten View erneut geladen wird. Gleiches gilt für die Notizen.
    @State private var controller: PDFReaderController?
    @State private var notes: NotesViewModel?
    @State private var showsSidebar = true
    @State private var sidebarMode: SidebarMode = .pages
    @State private var pendingText = ""
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
                AnnotationToolbar(controller: controller, onQuote: { quoteSelection(from: controller) }, canQuote: notes != nil)
                Divider()
                HSplitView {
                    HStack(spacing: 0) {
                        if showsSidebar {
                            sidebar(controller)
                                .frame(width: 200)
                            Divider()
                        }
                        PDFKitView(pdfView: controller.pdfView)
                    }
                    .frame(minWidth: 420)

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
                        .frame(minWidth: 280, idealWidth: 380, maxWidth: 640)
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

    // MARK: Seitenleiste

    @ViewBuilder
    private func sidebar(_ controller: PDFReaderController) -> some View {
        VStack(spacing: 0) {
            Picker("Seitenleiste", selection: $sidebarMode) {
                ForEach(SidebarMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()
            switch sidebarMode {
            case .pages:
                PDFThumbnailStrip(pdfView: controller.pdfView)
            case .annotations:
                AnnotationListView(controller: controller)
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
                    Image(systemName: "arrow.up.left.and.down.right.magnifyingglass")
                }
                .help("An Fenster anpassen")
            }

            Divider().frame(height: 16)

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
