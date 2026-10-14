import SwiftUI

struct StudySheetsView: View {
    @Bindable var viewModel: LearningViewModel
    @State private var pendingDeletion: StudySheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lernzettel")
                        .font(Theme.Typography.title)
                    Text("Strukturierte Zusammenstellungen aus deinen Notizen")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("Zum Erstellen Notizen auswählen")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
            Divider()

            if viewModel.studySheets.isEmpty {
                ContentUnavailableView(
                    "Noch keine Lernzettel",
                    systemImage: "doc.text",
                    description: Text("Gehe zu Notizen, wähle die passenden Einträge aus und erstelle daraus einen Lernzettel.")
                )
            } else {
                HSplitView {
                    List(selection: $viewModel.selectedStudySheetID) {
                        ForEach(viewModel.studySheets) { sheet in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(sheet.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text("\(sheet.sourceNoteIDs.count) Quellnotizen")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(sheet.updatedAt, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, 5)
                            .tag(sheet.id)
                            .contextMenu {
                                Button("Löschen", systemImage: "trash", role: .destructive) {
                                    pendingDeletion = sheet
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .frame(minWidth: 240, idealWidth: 280)

                    if let sheet = viewModel.studySheets.first(where: { $0.id == viewModel.selectedStudySheetID }) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(sheet.title)
                                        .font(Theme.Typography.title)
                                    Text("\(sheet.sourceNoteIDs.count) Quellnotizen · erstellt \(sheet.createdAt, style: .date)")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Menu {
                                    Button("Löschen", systemImage: "trash", role: .destructive) {
                                        pendingDeletion = sheet
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                }
                                .menuStyle(.borderlessButton)
                            }
                            .padding(18)
                            Divider()
                            MarkdownPreviewView(source: sheet.content)
                        }
                        .frame(minWidth: 400)
                    } else {
                        ContentUnavailableView("Lernzettel auswählen", systemImage: "doc.text")
                            .frame(minWidth: 400)
                    }
                }
            }
        }
        .background(Theme.background)
        .task { viewModel.load() }
        .confirmationDialog(
            "Lernzettel löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { sheet in
            Button("„\(sheet.title)“ löschen", role: .destructive) {
                viewModel.deleteSheet(sheet)
                pendingDeletion = nil
            }
        } message: { _ in
            Text("Der gespeicherte Lernzettel wird dauerhaft entfernt. Die ursprünglichen Notizen bleiben erhalten.")
        }
    }
}
