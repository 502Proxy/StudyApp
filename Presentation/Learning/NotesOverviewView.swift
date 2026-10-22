import AppKit
import SwiftUI

/// Alle Notizen eines Moduls an einem Ort: lesen, bearbeiten, neue Vorlesungsnotizen anlegen,
/// Karteikarten und Lernzettel daraus erstellen – ohne die Folien öffnen zu müssen.
struct NotesOverviewView: View {
    @Bindable var viewModel: LearningViewModel
    /// Öffnet eine Folien-Notiz im PDF-Reader an der passenden Seite.
    let onOpenInSlides: (LectureNote) -> Void

    @State private var isStudySheetPresented = false
    @State private var isCardEditorPresented = false
    @State private var cardDraft: FlashcardDraft?
    @State private var pendingDeletion: LectureNote?
    @State private var exportFile: NoteExportFile?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if viewModel.notes.isEmpty {
                EmptyStateView(
                    title: "Noch keine Notizen",
                    systemImage: "note.text",
                    message: "Schreibe eine Vorlesungsnotiz direkt hier oder öffne einen Foliensatz und notiere dir etwas zu einzelnen Seiten.",
                    actionTitle: "Neue Notiz",
                    action: { viewModel.addModuleNote() }
                )
            } else {
                HSplitView {
                    noteList
                        .frame(minWidth: 260, idealWidth: 310, maxWidth: 420)
                    noteDetail
                        .frame(minWidth: 380)
                }
            }
        }
        .background(Theme.background)
        .task { viewModel.load() }
        .onChange(of: viewModel.noteSearchQuery) { _, _ in
            if let selectedID = viewModel.selectedNoteID,
               !viewModel.visibleNotes.contains(where: { $0.id == selectedID }) {
                viewModel.selectedNoteID = viewModel.visibleNotes.first?.id
            }
        }
        .noteExporter(file: $exportFile) { viewModel.errorMessage = $0 }
        .sheet(isPresented: $isStudySheetPresented) {
            StudySheetCreateSheet(
                defaultTitle: "Lernzettel – \(viewModel.module.name)",
                selectedCount: viewModel.selectedNotesForStudySheet.count
            ) { title in
                viewModel.makeStudySheet(title: title)
            }
        }
        .sheet(isPresented: $isCardEditorPresented) {
            FlashcardEditorSheet(
                initialDraft: cardDraft,
                initialCard: nil,
                notes: viewModel.notes,
                sourceLabel: { note in viewModel.sourceLabel(for: note) },
                onSave: { draft in viewModel.saveCard(draft) }
            )
        }
        .confirmationDialog(
            "Notiz löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { note in
            Button("Notiz löschen", role: .destructive) {
                viewModel.deleteNote(note)
                pendingDeletion = nil
            }
        } message: { _ in
            Text("Die Notiz wird dauerhaft entfernt. Karteikarten und Lernzettel bleiben erhalten.")
        }
    }

    // MARK: Werkzeugleiste

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.textTertiary)
                TextField("Notizen durchsuchen", text: $viewModel.noteSearchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.surfaceBorder) }
            .frame(maxWidth: 280)

            Button {
                viewModel.addModuleNote()
            } label: {
                Label("Neue Notiz", systemImage: "square.and.pencil")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Neue Notiz ohne Folien (⌘N)")

            Menu {
                Button("Als Markdown-Datei …", systemImage: "doc.text") {
                    exportFile = NoteExportFile(
                        fileName: "\(NoteExportFormatting.safeFileName(viewModel.module.name))_Notizen.md",
                        text: viewModel.exportAllNotesAsMarkdown()
                    )
                }
                Button("Als PDF …", systemImage: "doc.richtext") {
                    PrintActions.exportPDF(viewModel.printableAllNotes(), into: $exportFile) { viewModel.errorMessage = $0 }
                }
                Divider()
                Button("Drucken …", systemImage: "printer") {
                    PrintActions.print(viewModel.printableAllNotes()) { viewModel.errorMessage = $0 }
                }
            } label: {
                Label("Alle exportieren", systemImage: "square.and.arrow.up")
            }
            .fixedSize()
            .disabled(!viewModel.notes.contains(where: \.hasContent))
            .help("Alle Notizen des Moduls als Markdown oder PDF sichern oder drucken")

            Spacer()

            if viewModel.selectedNoteIDs.isEmpty {
                Button("Für Lernzettel auswählen") { viewModel.selectAllVisibleNotes() }
                    .buttonStyle(.link)
                    .disabled(viewModel.visibleNotes.isEmpty)
            } else {
                Button("Auswahl aufheben") { viewModel.clearNoteSelection() }
                    .buttonStyle(.link)
            }

            Button {
                isStudySheetPresented = true
            } label: {
                Label("Lernzettel (\(viewModel.selectedNoteIDs.count))", systemImage: "doc.text")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedNoteIDs.isEmpty)
            .help("Markiere Notizen links, um daraus einen Lernzettel zu erstellen")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Liste

    private var noteList: some View {
        List(selection: $viewModel.selectedNoteID) {
            ForEach(viewModel.noteSections) { section in
                Section {
                    ForEach(section.notes) { note in
                        NoteListRow(
                            note: note,
                            title: rowTitle(for: note),
                            subtitle: rowSubtitle(for: note),
                            isSelectedForSheet: Binding(
                                get: { viewModel.selectedNoteIDs.contains(note.id) },
                                set: { viewModel.setNoteSelected(note.id, isSelected: $0) }
                            )
                        )
                        .tag(note.id)
                        .contextMenu {
                            if !viewModel.isModuleNote(note) {
                                Button("In den Folien öffnen") { onOpenInSlides(note) }
                            }
                            Button("Karteikarte aus Notiz erstellen") {
                                cardDraft = viewModel.draftForNote(note)
                                isCardEditorPresented = true
                            }
                            Divider()
                            Button("Löschen", role: .destructive) { pendingDeletion = note }
                        }
                    }
                } header: {
                    Label(section.title, systemImage: section.systemImage)
                        .lineLimit(1)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.surface)
        .overlay {
            if viewModel.visibleNotes.isEmpty {
                ContentUnavailableView.search(text: viewModel.noteSearchQuery)
            }
        }
    }

    private func rowTitle(for note: LectureNote) -> String {
        if viewModel.isModuleNote(note) { return note.title }
        return note.pageNumber.map { "Seite \($0)" } ?? "Gesamtdokument"
    }

    private func rowSubtitle(for note: LectureNote) -> String {
        note.previewLine() ?? "Noch leer"
    }

    // MARK: Detail

    @ViewBuilder
    private var noteDetail: some View {
        if let note = viewModel.selectedNote {
            NoteDetailPane(
                session: viewModel.makeEditingSession(for: note),
                isModuleNote: viewModel.isModuleNote(note),
                sourceLabel: viewModel.sourceLabel(for: note),
                onOpenInSlides: { onOpenInSlides(note) },
                onCreateCard: {
                    cardDraft = viewModel.draftForNote(note)
                    isCardEditorPresented = true
                },
                onExport: {
                    if let content = viewModel.exportContent(forNoteWithID: note.id) {
                        exportFile = NoteExportFile(fileName: content.fileName, text: content.text)
                    }
                },
                onExportPDF: {
                    if let document = viewModel.printableNote(withID: note.id) {
                        PrintActions.exportPDF(document, into: $exportFile) { viewModel.errorMessage = $0 }
                    }
                },
                onPrint: {
                    if let document = viewModel.printableNote(withID: note.id) {
                        PrintActions.print(document) { viewModel.errorMessage = $0 }
                    }
                },
                onDelete: { pendingDeletion = note }
            )
            .id(note.id)
        } else {
            EmptyStateView(
                title: "Notiz auswählen",
                systemImage: "note.text",
                message: "Wähle links eine Notiz aus, um sie zu lesen oder zu bearbeiten."
            )
        }
    }
}

private struct NoteListRow: View {
    let note: LectureNote
    let title: String
    let subtitle: String
    @Binding var isSelectedForSheet: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("Für Lernzettel auswählen", isOn: $isSelectedForSheet)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .padding(.top, 2)
                .help("Für einen Lernzettel auswählen")

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title)
                        .font(Theme.Typography.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(note.updatedAt, format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(subtitle)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Lese- und Bearbeitungsansicht einer Notiz mit Autosave.
private struct NoteDetailPane: View {
    @State private var session: NoteEditingSession
    let isModuleNote: Bool
    let sourceLabel: String
    let onOpenInSlides: () -> Void
    let onCreateCard: () -> Void
    let onExport: () -> Void
    let onExportPDF: () -> Void
    let onPrint: () -> Void
    let onDelete: () -> Void

    @State private var mode: NoteEditorView.ViewMode
    @AppStorage(ViewPreferences.noteFontSizeKey) private var fontSize = NoteFontSize.standard

    init(
        session: NoteEditingSession,
        isModuleNote: Bool,
        sourceLabel: String,
        onOpenInSlides: @escaping () -> Void,
        onCreateCard: @escaping () -> Void,
        onExport: @escaping () -> Void,
        onExportPDF: @escaping () -> Void,
        onPrint: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        _session = State(initialValue: session)
        self.isModuleNote = isModuleNote
        self.sourceLabel = sourceLabel
        self.onOpenInSlides = onOpenInSlides
        self.onCreateCard = onCreateCard
        self.onExport = onExport
        self.onExportPDF = onExportPDF
        self.onPrint = onPrint
        self.onDelete = onDelete
        // Vorhandenes zuerst lesen, eine neue Notiz direkt bearbeiten.
        let isBlank = session.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || session.content.trimmingCharacters(in: .whitespacesAndNewlines) == "# \(session.title)"
        _mode = State(initialValue: isBlank || !session.format.hasPreview ? .edit : .preview)
    }

    private var effectiveMode: NoteEditorView.ViewMode {
        session.format.hasPreview ? mode : .edit
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch effectiveMode {
            case .edit:
                editor
            case .preview:
                preview
            case .split:
                HSplitView {
                    editor.frame(minWidth: 220)
                    preview.frame(minWidth: 220)
                }
            }
        }
        .background(Theme.editorBackground)
        .environment(\.noteFontSize, fontSize)
        .onChange(of: session.content) { _, _ in session.noteDidChange() }
        .onChange(of: session.title) { _, _ in session.noteDidChange() }
        .onChange(of: session.format) { _, _ in session.noteDidChange() }
        .onDisappear { session.saveNow() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            session.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.saveNow()
        }
        .errorAlert(message: session.errorMessage) { session.errorMessage = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if isModuleNote {
                    TextField("Titel", text: $session.title)
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.title)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sourceLabel)
                            .font(Theme.Typography.title)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                SaveIndicator(state: session.saveState)
                NoteFontSizeControl()
                if !isModuleNote {
                    Button(action: onOpenInSlides) {
                        Label("In Folien öffnen", systemImage: "doc.richtext")
                    }
                    .help("Foliensatz an dieser Stelle öffnen")
                }
                Menu {
                    Button("Karteikarte erstellen", systemImage: "rectangle.stack.badge.plus", action: onCreateCard)
                    Button("Notiz exportieren …", systemImage: "square.and.arrow.up") {
                        // Vor dem Export speichern, damit die Datei den aktuellen Stand enthält.
                        session.saveNow()
                        onExport()
                    }
                    Button("Als PDF exportieren …", systemImage: "doc.richtext") {
                        session.saveNow()
                        onExportPDF()
                    }
                    Button("Drucken …", systemImage: "printer") {
                        session.saveNow()
                        onPrint()
                    }
                    Divider()
                    Button("Notiz löschen", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 12) {
                Picker("Format", selection: $session.format) {
                    ForEach(NoteFormat.allCases, id: \.self) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()

                if session.format.hasPreview {
                    Picker("Ansicht", selection: $mode) {
                        Label("Bearbeiten", systemImage: "pencil").tag(NoteEditorView.ViewMode.edit)
                        Label("Geteilt", systemImage: "rectangle.split.2x1").tag(NoteEditorView.ViewMode.split)
                        Label("Lesen", systemImage: "eye").tag(NoteEditorView.ViewMode.preview)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                Text("\(session.content.split { $0.isWhitespace || $0.isNewline }.count) Wörter")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $session.content)
                .font(.system(size: fontSize, design: session.format == .plainText ? .default : .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled(session.format.hasPreview)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            if session.content.isEmpty {
                Text(session.format.placeholder)
                    .font(.system(size: fontSize))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 21)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.editorBackground)
    }

    @ViewBuilder
    private var preview: some View {
        if session.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyStateView(title: "Noch leer", systemImage: "eye.slash", message: "Wechsle zu „Bearbeiten“, um loszuschreiben.")
        } else {
            switch session.format {
            case .markdown:
                MarkdownPreviewView(source: session.content)
            case .latex:
                LaTeXPreviewView(source: session.content)
            case .plainText:
                ScrollView {
                    Text(session.content)
                        .font(.system(size: fontSize))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(20)
                }
                .background(Theme.editorBackground)
            }
        }
    }
}

/// Kleiner Autosave-Hinweis.
struct SaveIndicator: View {
    let state: NotesViewModel.SaveState
    /// Nur das Symbol, für schmale Bereiche; der Text steht dann im Tooltip.
    var isCompact = false

    private var title: String {
        switch state {
        case .saved: "Gespeichert"
        case .pending: "Speichert …"
        case .failed: "Nicht gespeichert"
        }
    }

    var body: some View {
        Group {
            switch state {
            case .saved:
                Label("Gespeichert", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.textTertiary)
            case .pending:
                Label("Speichert …", systemImage: "ellipsis.circle")
                    .foregroundStyle(Theme.textSecondary)
            case .failed:
                Label("Nicht gespeichert", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Theme.danger)
            }
        }
        .font(Theme.Typography.small)
        .labelStyle(TitleAndIconOrIconOnly(isCompact: isCompact))
        .help(title)
    }
}

private struct TitleAndIconOrIconOnly: LabelStyle {
    let isCompact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isCompact {
            configuration.icon
        } else {
            Label(configuration)
        }
    }
}
