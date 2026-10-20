import SwiftUI

struct FlashcardEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notes: [LectureNote]
    let sourceLabel: (LectureNote) -> String
    let onSave: (FlashcardDraft) -> Bool

    private let cardID: UUID?
    @State private var question: String
    @State private var answer: String
    @State private var sourceNoteID: UUID?

    init(
        initialDraft: FlashcardDraft? = nil,
        initialCard: Flashcard? = nil,
        notes: [LectureNote],
        sourceLabel: @escaping (LectureNote) -> String,
        onSave: @escaping (FlashcardDraft) -> Bool
    ) {
        self.notes = notes
        self.sourceLabel = sourceLabel
        self.onSave = onSave
        cardID = initialCard?.id ?? initialDraft?.id
        _question = State(initialValue: initialDraft?.question ?? initialCard?.front ?? "")
        _answer = State(initialValue: initialDraft?.answer ?? initialCard?.back ?? "")
        _sourceNoteID = State(initialValue: initialDraft?.sourceNoteID ?? initialCard?.sourceNoteID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(cardID == nil ? "Neue Karteikarte" : "Karteikarte bearbeiten")
                .font(Theme.Typography.title)

            Form {
                Section("Vorderseite · Frage") {
                    TextEditor(text: $question)
                        .frame(minHeight: 80)
                }
                Section("Rückseite · Antwort") {
                    TextEditor(text: $answer)
                        .frame(minHeight: 130)
                }
                Section("Quelle (optional)") {
                    Picker("Notiz", selection: $sourceNoteID) {
                        Text("Keine Quelle").tag(nil as UUID?)
                        ForEach(notes) { note in
                            Text(sourceLabel(note)).tag(Optional(note.id))
                        }
                    }
                    .labelsHidden()
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                Button("Speichern") {
                    let draft = FlashcardDraft(
                        id: cardID,
                        question: question,
                        answer: answer,
                        sourceNoteID: sourceNoteID
                    )
                    if onSave(draft) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 500)
    }
}
