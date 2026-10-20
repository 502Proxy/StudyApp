import SwiftUI

struct ModuleEditorSheet: View {
    let mode: ModuleEditorMode
    let onSave: (ModuleDraft) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: ModuleDraft

    init(mode: ModuleEditorMode, onSave: @escaping (ModuleDraft) -> Bool) {
        self.mode = mode
        self.onSave = onSave
        _draft = State(initialValue: mode.draft)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(mode.title)
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .top], 20)

            Form {
                TextField("Name", text: $draft.name)
                TextField("Kürzel (optional)", text: $draft.code)

                LabeledContent("Farbe") {
                    HStack(spacing: 10) {
                        ForEach(ModuleColor.allCases, id: \.self) { color in
                            Button {
                                draft.color = color
                            } label: {
                                ColorDot(color: color, size: 18, isSelected: draft.color == color)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Abbrechen", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    if onSave(draft) { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 480)
        .background(Theme.surface)
    }
}
