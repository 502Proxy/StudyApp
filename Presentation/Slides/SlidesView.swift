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
                    makeNotesViewModel: { viewModel.makeNotesViewModel(for: document) },
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
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: Liste

    private var library: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Folien")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    viewModel.isImporterPresented = true
                } label: {
                    Label("PDF importieren", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 16)

            if viewModel.documents.isEmpty {
                ContentUnavailableView {
                    Label("Noch keine Folien", systemImage: "doc.richtext")
                } description: {
                    Text("Importiere PDFs über den Button oder ziehe sie in dieses Fenster.")
                } actions: {
                    Button("PDF importieren") {
                        viewModel.isImporterPresented = true
                    }
                }
            } else {
                List {
                    ForEach(viewModel.documents) { document in
                        Button {
                            viewModel.open(document)
                        } label: {
                            SlideRow(document: document)
                        }
                        .buttonStyle(.plain)
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
                .padding(.horizontal, 20)
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

    private var subtitle: String {
        let pages = document.pageCount == 1 ? "1 Seite" : "\(document.pageCount) Seiten"
        let date = document.importedAt.formatted(date: .abbreviated, time: .omitted)
        return "\(pages) · importiert am \(date)"
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 20))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(document.title)
                    .font(Theme.Typography.body.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Theme.surfaceBorder)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .padding(.vertical, 3)
    }
}
