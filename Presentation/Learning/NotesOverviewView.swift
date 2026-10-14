import SwiftUI

struct NotesOverviewView: View {
    @Bindable var viewModel: LearningViewModel
    @State private var isStudySheetPresented = false
    @State private var isCardEditorPresented = false
    @State private var cardDraft: FlashcardDraft?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            if viewModel.notes.isEmpty {
                ContentUnavailableView(
                    "Noch keine Notizen",
                    systemImage: "note.text",
                    description: Text("Öffne einen Foliensatz und schreibe Notizen. Sie erscheinen hier gesammelt.")
                )
            } else {
                HSplitView {
                    noteList
                        .frame(minWidth: 260, idealWidth: 330)
                    noteDetail
                        .frame(minWidth: 360)
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
                sourceLabel: { note in viewModel.sourceLabel(for: note) }
            ) { draft in
                viewModel.saveCard(draft)
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Notizen durchsuchen …", text: $viewModel.noteSearchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            Button("Alle sichtbaren auswählen") {
                viewModel.selectAllVisibleNotes()
            }
            .disabled(viewModel.visibleNotes.isEmpty)

            Button("Auswahl aufheben") {
                viewModel.clearNoteSelection()
            }
            .disabled(viewModel.selectedNoteIDs.isEmpty)

            Spacer()

            Button {
                isStudySheetPresented = true
            } label: {
                Label("Lernzettel erstellen (\(viewModel.selectedNoteIDs.count))", systemImage: "doc.text")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedNoteIDs.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var noteList: some View {
        List(selection: $viewModel.selectedNoteID) {
            ForEach(viewModel.visibleNotes) { note in
                HStack(alignment: .top, spacing: 10) {
                    Toggle(
                        "Für Lernzettel auswählen",
                        isOn: Binding(
                            get: { viewModel.selectedNoteIDs.contains(note.id) },
                            set: { viewModel.setNoteSelected(note.id, isSelected: $0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                    .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.sourceDocumentTitle(for: note))
                            .font(.headline)
                            .lineLimit(2)
                        Text(note.pageNumber.map { "Seite \($0)" } ?? "Gesamtdokument")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Text(note.content.replacingOccurrences(of: "\n", with: " "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 5)
                .tag(note.id)
                .contextMenu {
                    Button("Karteikarte aus Notiz erstellen") {
                        cardDraft = viewModel.draftForNote(note)
                        isCardEditorPresented = true
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if viewModel.visibleNotes.isEmpty {
                ContentUnavailableView.search(text: viewModel.noteSearchQuery)
            }
        }
    }

    @ViewBuilder
    private var noteDetail: some View {
        if let note = viewModel.selectedNote {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(viewModel.sourceDocumentTitle(for: note))
                            .font(Theme.Typography.title)
                        Text(viewModel.sourceLabel(for: note))
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Button {
                        cardDraft = viewModel.draftForNote(note)
                        isCardEditorPresented = true
                    } label: {
                        Label("Karteikarte", systemImage: "rectangle.stack.badge.plus")
                    }
                }
                .padding(20)
                Divider()

                Group {
                    switch note.format {
                    case .markdown:
                        MarkdownPreviewView(source: note.content)
                    case .latex:
                        LaTeXPreviewView(source: note.content)
                    case .plainText:
                        ScrollView {
                            Text(note.content)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(20)
                        }
                        .background(Theme.editorBackground)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Notiz auswählen",
                systemImage: "note.text",
                description: Text("Wähle links eine Notiz aus, um sie zu lesen.")
            )
        }
    }
}
