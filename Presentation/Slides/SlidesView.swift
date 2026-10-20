import SwiftUI
import UniformTypeIdentifiers

/// Folien eines Moduls: Liste mit Import, oder der Viewer, wenn ein Dokument geöffnet ist.
struct SlidesView: View {
    @Bindable var viewModel: SlidesViewModel

    @State private var renaming: SlideDocument?
    @State private var renameText = ""
    @State private var pendingDeletion: SlideDocument?
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if let document = viewModel.openDocument {
                SlideReaderView(
                    document: document,
                    fileURL: viewModel.fileURL(for: document),
                    requestedPage: viewModel.requestedPage,
                    pageRequestID: viewModel.pageRequestID,
                    makeNotesViewModel: { viewModel.makeNotesViewModel(for: document) },
                    saveDocument: { try viewModel.saveAnnotatedDocument($0, for: document) },
                    onPageChange: { viewModel.recordPage($0, for: document) },
                    onClose: { viewModel.close() }
                )
                .id(document.id)
            } else {
                library
            }
        }
        .task { viewModel.load() }
        .fileImporter(
            isPresented: $viewModel.isImporterPresented,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.importPDFs(urls)
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .errorAlert(message: viewModel.errorMessage) { viewModel.errorMessage = nil }
    }

    // MARK: Liste

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(
                "Folien",
                subtitle: viewModel.documents.isEmpty ? nil : "\(viewModel.documents.count) Foliensätze · Ziehe PDFs hierher, um sie hinzuzufügen"
            ) {
                if let resume = viewModel.documentToResume {
                    Button {
                        viewModel.open(resume)
                    } label: {
                        Label("Weiterlesen", systemImage: "book")
                    }
                    .help("„\(resume.title)“ an der letzten Stelle öffnen")
                }
                Button {
                    viewModel.isImporterPresented = true
                } label: {
                    Label("PDF importieren", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.vertical, 16)

            if viewModel.documents.isEmpty {
                EmptyStateView(
                    title: "Noch keine Folien",
                    systemImage: "doc.richtext",
                    message: "Importiere die PDF-Folien deiner Vorlesung oder ziehe sie in dieses Fenster. Während der Vorlesung öffnet StudyApp sie dann automatisch.",
                    actionTitle: "PDF importieren",
                    action: { viewModel.isImporterPresented = true }
                )
            } else {
                List {
                    ForEach(viewModel.documents) { document in
                        Button {
                            viewModel.open(document)
                        } label: {
                            SlideRow(
                                document: document,
                                lastPage: viewModel.lastPage(for: document),
                                isLastRead: viewModel.documentToResume?.id == document.id
                            )
                        }
                        .buttonStyle(CardButtonStyle())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("Öffnen") { viewModel.open(document) }
                            Button("Umbenennen") {
                                renameText = document.title
                                renaming = document
                            }
                            Divider()
                            Button("Löschen", role: .destructive) {
                                pendingDeletion = document
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, Theme.Spacing.page - 8)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            guard !pdfs.isEmpty else { return false }
            viewModel.importPDFs(pdfs)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .alert(
            "Folien umbenennen",
            isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )
        ) {
            TextField("Titel", text: $renameText)
            Button("Sichern") {
                if let renaming {
                    viewModel.rename(renaming, to: renameText)
                }
                renaming = nil
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog(
            "Folien löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { document in
            Button("„\(document.title)“ löschen", role: .destructive) {
                viewModel.delete(document)
            }
        } message: { _ in
            Text("Die PDF, alle Markierungen darin und die zugehörigen Notizen werden entfernt.")
        }
    }
}

private struct SlideRow: View {
    let document: SlideDocument
    let lastPage: Int?
    let isLastRead: Bool

    private var subtitle: String {
        let pages = document.pageCount == 1 ? "1 Seite" : "\(document.pageCount) Seiten"
        let date = document.importedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(pages) · importiert am \(date)"
    }

    private var progress: Double {
        guard let lastPage, document.pageCount > 1 else { return 0 }
        return Double(lastPage - 1) / Double(document.pageCount - 1)
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.accent)
                .frame(width: 42, height: 42)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(document.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if isLastRead {
                        Pill(text: "Zuletzt gelesen", tint: Theme.accent)
                    }
                }
                Text(subtitle)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
                if let lastPage, lastPage > 1 {
                    HStack(spacing: 8) {
                        SlimProgressBar(progress: progress)
                            .frame(maxWidth: 160)
                        Text("Seite \(lastPage)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .card(padding: 12, radius: Theme.Radius.medium)
        .padding(.vertical, 3)
    }
}
