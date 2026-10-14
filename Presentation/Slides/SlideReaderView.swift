import SwiftUI

/// PDF-Viewer mit Werkzeugleiste: Seitenwechsel, Zoom, Markieren, Vorschaubilder
/// und einer ein- und ausblendbaren Notizen-Seitenleiste.
struct SlideReaderView: View {
    let document: SlideDocument
    let fileURL: URL
    let makeNotesViewModel: () -> NotesViewModel
    let onClose: () -> Void

    // Der Controller entsteht erst beim Erscheinen, damit das PDF nicht bei jedem
    // Neuaufbau der übergeordneten View erneut geladen wird. Gleiches gilt für die Notizen.
    @State private var controller: PDFReaderController?
    @State private var notes: NotesViewModel?
    @State private var showsThumbnails = true
    @AppStorage("slideReader.showsNotes") private var showsNotes = false

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
                controller = PDFReaderController(fileURL: fileURL)
            }
            if notes == nil {
                let viewModel = makeNotesViewModel()
                viewModel.load()
                notes = viewModel
            }
        }
    }

    @ViewBuilder
    private func content(_ controller: PDFReaderController) -> some View {
        if controller.isLoaded {
            VStack(spacing: 0) {
                toolbar(controller)
                Divider()
                HSplitView {
                    HStack(spacing: 0) {
                        if showsThumbnails {
                            PDFThumbnailStrip(pdfView: controller.pdfView)
                                .frame(width: 150)
                            Divider()
                        }
                        PDFKitView(pdfView: controller.pdfView)
                    }
                    .frame(minWidth: 380)

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
            .alert(
                "Fehler",
                isPresented: Binding(
                    get: { controller.errorMessage != nil },
                    set: { if !$0 { controller.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.errorMessage ?? "")
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

    private var backButton: some View {
        Button(action: onClose) {
            Label("Folien", systemImage: "chevron.left")
        }
        .buttonStyle(.borderless)
    }

    private func toolbar(_ controller: PDFReaderController) -> some View {
        HStack(spacing: 14) {
            backButton

            Text(document.title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 8) {
                Button { controller.goToPreviousPage() } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(controller.pageIndex <= 0)
                .help("Vorherige Seite")

                Text("Seite \(controller.pageIndex + 1) von \(controller.pageCount)")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)

                Button { controller.goToNextPage() } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(controller.pageIndex >= controller.pageCount - 1)
                .help("Nächste Seite")
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

            HStack(spacing: 8) {
                Button { controller.highlightSelection() } label: {
                    Image(systemName: "highlighter")
                }
                .disabled(!controller.hasSelection)
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .help("Auswahl markieren (⇧⌘H)")

                Button { controller.removeHighlightsInSelection() } label: {
                    Image(systemName: "eraser")
                }
                .disabled(!controller.hasSelection)
                .help("Markierung in der Auswahl entfernen")
            }

            Divider().frame(height: 16)

            Button {
                showsThumbnails.toggle()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Vorschaubilder ein- oder ausblenden")

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
        .background(.bar)
    }
}
