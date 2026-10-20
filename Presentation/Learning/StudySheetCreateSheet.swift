import SwiftUI

struct StudySheetCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedCount: Int
    let onCreate: (String) -> Bool
    @State private var title: String

    init(defaultTitle: String, selectedCount: Int, onCreate: @escaping (String) -> Bool) {
        self.selectedCount = selectedCount
        self.onCreate = onCreate
        _title = State(initialValue: defaultTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Lernzettel erstellen")
                .font(Theme.Typography.title)
            Text("Aus \(selectedCount) ausgewählten Notizen wird ein strukturierter Markdown-Lernzettel erstellt. Originaltexte und Formeln bleiben erhalten; Überschriften und Selbstkontrollfragen werden ergänzt.")
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Titel", text: $title)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                Button("Erstellen") {
                    if onCreate(title) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedCount == 0)
            }
        }
        .padding(22)
        .frame(width: 480, height: 270)
    }
}
