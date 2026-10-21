import AppKit
import SwiftUI

/// Bereich „Dateien“ eines Moduls: alle Dateien der verknüpften Stud.IP-Veranstaltung.
struct CourseFilesView: View {
    @Bindable var viewModel: CourseFilesViewModel
    /// Vom aktuellen Modul, weil sich die Verknüpfung ändern kann, während der Bereich offen ist.
    let isLinked: Bool
    let isSyncing: Bool
    let lastSync: Date?
    let onSync: () -> Void
    let onLink: () -> Void
    let onOpenSlides: (UUID) -> Void

    var body: some View {
        Group {
            if !isLinked {
                EmptyStateView(
                    title: "Keine Stud.IP-Veranstaltung",
                    systemImage: "folder.badge.questionmark",
                    message: "Verknüpfe das Modul mit seiner Veranstaltung. Danach erscheinen hier alle Dateien aus dem Stud.IP-Dateibereich und werden automatisch heruntergeladen.",
                    actionTitle: "Veranstaltung zuordnen …",
                    action: onLink
                )
            } else if viewModel.files.isEmpty {
                EmptyStateView(
                    title: isSyncing ? "Dateien werden geladen …" : "Noch keine Dateien",
                    systemImage: "folder",
                    message: viewModel.isConnected
                        ? "Beim nächsten Abgleich lädt StudyApp die Dateien der Veranstaltung."
                        : "Melde dich in den Einstellungen (⌘,) bei Stud.IP an.",
                    actionTitle: viewModel.isConnected && !isSyncing ? "Jetzt abgleichen" : nil,
                    action: onSync
                )
            } else {
                fileList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .errorAlert(message: viewModel.errorMessage) { viewModel.errorMessage = nil }
        .task { viewModel.load() }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("Dateien durchsuchen", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Text(summary)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer()
                if isSyncing {
                    ProgressView().controlSize(.small)
                }
                Button(action: onSync) {
                    Label("Abgleichen", systemImage: "arrow.clockwise")
                }
                .disabled(isSyncing || !viewModel.isConnected)
                .help("Neue Dateien aus Stud.IP laden")
            }
            .padding(.horizontal, Theme.Spacing.page)

            List {
                ForEach(viewModel.folders) { folder in
                    Section(folder.title) {
                        ForEach(folder.files) { file in
                            CourseFileRow(
                                file: file,
                                isDownloading: viewModel.downloading.contains(file.id),
                                onDownload: { Task { await viewModel.fetch(file) } }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { open(file) }
                            .contextMenu { menu(for: file) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .padding(.top, 4)
    }

    private var summary: String {
        var text = "\(viewModel.files.count) Dateien · \(viewModel.downloadedCount) lokal"
        if let lastSync {
            text += " · Stand \(lastSync.formatted(date: .omitted, time: .shortened))"
        }
        return text
    }

    @ViewBuilder
    private func menu(for file: CourseFile) -> some View {
        Button("Öffnen") { open(file) }
        if let url = viewModel.localURL(of: file) {
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
        Button(file.isDownloaded ? "Erneut laden" : "Herunterladen") {
            Task { await viewModel.fetch(file) }
        }
    }

    private func open(_ file: CourseFile) {
        Task {
            switch await viewModel.openAction(for: file) {
            case .slides(let documentID): onOpenSlides(documentID)
            case .file(let url): NSWorkspace.shared.open(url)
            case nil: break
            }
        }
    }
}

private struct CourseFileRow: View {
    let file: CourseFile
    let isDownloading: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(for: file))
                .font(.system(size: 16))
                .foregroundStyle(file.isPDF ? Theme.danger : Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(details)
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            status
        }
        .padding(.vertical, 3)
    }

    private var details: String {
        var parts: [String] = []
        if let size = file.size {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if let changedAt = file.changedAt {
            parts.append(changedAt.formatted(date: .abbreviated, time: .omitted))
        }
        if file.isPDF { parts.append("in den Folien") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var status: some View {
        if isDownloading {
            ProgressView().controlSize(.small)
        } else if file.isOutdated {
            Button(action: onDownload) {
                Pill(text: "Neue Fassung", systemImage: "arrow.down.circle", tint: Theme.warning)
            }
            .buttonStyle(.plain)
            .help("Neue Fassung aus Stud.IP laden")
        } else if file.isDownloaded {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.success)
                .help("Heruntergeladen")
        } else if !file.isPDF {
            Button(action: onDownload) {
                Image(systemName: "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .help("Herunterladen")
        }
    }

    static func symbol(for file: CourseFile) -> String {
        switch file.fileExtension {
        case "pdf": "doc.richtext"
        case "doc", "docx", "odt", "rtf", "txt", "md": "doc.text"
        case "xls", "xlsx", "ods", "csv": "tablecells"
        case "ppt", "pptx", "odp", "key": "rectangle.on.rectangle"
        case "zip", "tar", "gz", "rar", "7z": "doc.zipper"
        case "png", "jpg", "jpeg", "gif", "heic", "svg": "photo"
        case "mp4", "mov", "m4v", "avi", "mkv": "film"
        case "mp3", "m4a", "wav": "waveform"
        case "py", "java", "c", "cpp", "h", "swift", "js", "ts", "html", "css", "ipynb", "r", "m", "tex": "chevron.left.forwardslash.chevron.right"
        default: "doc"
        }
    }
}
