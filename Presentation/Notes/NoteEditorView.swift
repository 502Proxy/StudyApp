import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Note pane next to the slides: scope picker, editor, search, export and live preview.
struct NoteEditorView: View {
    @Bindable var viewModel: NotesViewModel
    let currentPageNumber: Int
    let onSelectNote: (LectureNote) -> Void

    @State private var mode: ViewMode = .split
    @State private var showsSearch = false
    @AppStorage(ViewPreferences.noteFontSizeKey) private var fontSize = NoteFontSize.standard

    enum ViewMode: String, CaseIterable, Identifiable {
        case edit = "Text"
        case split = "Beides"
        case preview = "Vorschau"

        var id: Self { self }
    }

    private enum NoteScope: Hashable {
        case document
        case page
    }

    private var selectedScope: Binding<NoteScope> {
        Binding(
            get: { viewModel.pageNumber == nil ? .document : .page },
            set: { scope in
                switch scope {
                case .document: viewModel.selectPageNumber(nil)
                case .page: viewModel.selectPageNumber(currentPageNumber)
                }
            }
        )
    }

    private var effectiveMode: ViewMode {
        viewModel.format.hasPreview ? mode : .edit
    }

    private var isContentBlank: Bool {
        viewModel.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showsSearch {
                searchPanel
                Divider()
            }
            switch effectiveMode {
            case .edit:
                editor
            case .preview:
                preview
            case .split:
                VSplitView {
                    editor.frame(minHeight: 120)
                    preview.frame(minHeight: 120)
                }
            }
        }
        .background(Theme.background)
        .environment(\.noteFontSize, fontSize)
        .onChange(of: viewModel.content) { viewModel.noteDidChange() }
        .onChange(of: viewModel.format) { viewModel.noteDidChange() }
        .onChange(of: currentPageNumber) { _, newPageNumber in
            // When page scope is active, keep the note attached to the PDF's visible page.
            if viewModel.pageNumber != nil, viewModel.pageNumber != newPageNumber {
                viewModel.selectPageNumber(newPageNumber)
            }
        }
        .onDisappear { viewModel.saveNow() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            viewModel.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.saveNow()
        }
        .errorAlert(message: viewModel.errorMessage) { viewModel.errorMessage = nil }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notizen")
                    .font(Theme.Typography.sectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                SaveIndicator(state: viewModel.saveState)
                NoteFontSizeControl()

                Button {
                    showsSearch.toggle()
                    if !showsSearch { viewModel.searchQuery = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("Notizen dieses Foliensatzes durchsuchen")

                Menu {
                    Button {
                        exportCurrentNote()
                    } label: {
                        Label("Aktuelle Notiz exportieren", systemImage: "doc.text")
                    }
                    .disabled(viewModel.currentNoteForExport() == nil)

                    Button {
                        exportAllNotes()
                    } label: {
                        Label("Alle Notizen exportieren", systemImage: "doc.on.doc")
                    }
                    .disabled(!viewModel.hasExportableNotes)
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .help("Notizen exportieren")
            }

            HStack(spacing: 12) {
                Picker("Notiz für", selection: selectedScope) {
                    Text("Gesamtdokument").tag(NoteScope.document)
                    Text("Seite \(currentPageNumber)").tag(NoteScope.page)
                }
                .pickerStyle(.menu)
                .fixedSize()
                .help("Zwischen dokumentweiten und seitenspezifischen Notizen wechseln")

                Picker("Format", selection: $viewModel.format) {
                    ForEach(NoteFormat.allCases, id: \.self) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                if viewModel.format.hasPreview {
                    Picker("Ansicht", selection: $mode) {
                        ForEach(ViewMode.allCases) { viewMode in
                            Text(viewMode.rawValue).tag(viewMode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("In Notizen dieses Foliensatzes suchen", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)

            if viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Durchsucht dokumentweite und seitenspezifische Notizen.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else if viewModel.searchResults.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchQuery)
                    .frame(minHeight: 70, maxHeight: 100)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.searchResults) { note in
                            Button {
                                viewModel.saveNow()
                                viewModel.selectNote(note)
                                onSelectNote(note)
                                showsSearch = false
                                viewModel.searchQuery = ""
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(note.pageNumber.map { "Seite \($0)" } ?? "Gesamtdokument")
                                        .font(Theme.Typography.body.weight(.medium))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(note.content.replacingOccurrences(of: "\n", with: " "))
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
        }
        .padding(12)
        .background(Theme.background)
    }

    // MARK: Editor and preview

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.content)
                .font(.system(size: fontSize, design: viewModel.format == .plainText ? .default : .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                // Smart punctuation would corrupt Markdown and LaTeX source.
                .autocorrectionDisabled(viewModel.format.hasPreview)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            if viewModel.content.isEmpty {
                Text(viewModel.format.placeholder)
                    .font(.system(size: fontSize))
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
                    .padding(.horizontal, 17)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.editorBackground)
    }

    @ViewBuilder
    private var preview: some View {
        if isContentBlank {
            ContentUnavailableView(
                "Keine Vorschau",
                systemImage: "eye.slash",
                description: Text("Schreibe etwas, um die Vorschau zu sehen.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch viewModel.format {
            case .plainText:
                EmptyView()
            case .markdown:
                MarkdownPreviewView(source: viewModel.content)
            case .latex:
                LaTeXPreviewView(source: viewModel.content)
            }
        }
    }

    // MARK: Export

    private func exportCurrentNote() {
        guard let note = viewModel.currentNoteForExport() else { return }
        let fileExtension: String
        switch note.format {
        case .plainText: fileExtension = "txt"
        case .markdown: fileExtension = "md"
        case .latex: fileExtension = "tex"
        }
        let scope = note.pageNumber.map { "_Seite_\($0)" } ?? "_Gesamtdokument"
        presentSavePanel(
            content: note.content,
            fileName: "\(safeFileName(documentTitle: viewModel.document.title))\(scope).\(fileExtension)",
            fileExtension: fileExtension
        )
    }

    private func exportAllNotes() {
        let content = viewModel.exportAllNotesAsMarkdown()
        presentSavePanel(
            content: content,
            fileName: "\(safeFileName(documentTitle: viewModel.document.title))_Notizen.md",
            fileExtension: "md"
        )
    }

    private func presentSavePanel(content: String, fileName: String, fileExtension: String) {
        let panel = NSSavePanel()
        panel.title = "Notizen exportieren"
        panel.nameFieldStringValue = fileName
        panel.allowedContentTypes = [UTType(filenameExtension: fileExtension) ?? .plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            viewModel.errorMessage = "Der Export ist fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func safeFileName(documentTitle: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\0")
        let cleaned = documentTitle.components(separatedBy: invalidCharacters).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Notizen" : cleaned
    }
}
