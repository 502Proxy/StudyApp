import SwiftUI

struct FlashcardsView: View {
    @Bindable var viewModel: LearningViewModel
    @State private var isEditorPresented = false
    @State private var editingCard: Flashcard?
    @State private var editorDraft: FlashcardDraft?
    @State private var pendingDeletion: Flashcard?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if viewModel.isReviewSessionActive {
                reviewContent
            } else {
                cardList
            }
        }
        .background(Theme.background)
        .task { viewModel.load() }
        .sheet(isPresented: $isEditorPresented) {
            FlashcardEditorSheet(
                initialDraft: editorDraft,
                initialCard: editingCard,
                notes: viewModel.notes,
                sourceLabel: { note in viewModel.sourceLabel(for: note) }
            ) { draft in
                viewModel.saveCard(draft)
            }
        }
        .confirmationDialog(
            "Karteikarte löschen?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { card in
            Button("Karte löschen", role: .destructive) {
                viewModel.deleteCard(card)
                pendingDeletion = nil
            }
        } message: { _ in
            Text("Diese Karte wird dauerhaft aus dem Modul entfernt.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Karteikarten")
                    .font(Theme.Typography.title)
                HStack(spacing: 6) {
                    Pill(text: "\(viewModel.flashcards.count) Karten")
                    Pill(text: "\(viewModel.dueFlashcards.count) fällig", tint: viewModel.dueFlashcards.isEmpty ? Theme.textSecondary : Theme.warning)
                    Pill(text: "\(viewModel.reviewedTodayCount) heute wiederholt", tint: Theme.success)
                }
            }
            Spacer()
            Button {
                editingCard = nil
                editorDraft = nil
                isEditorPresented = true
            } label: {
                Label("Neue Karte", systemImage: "plus")
            }
            Button {
                viewModel.startReviewSession()
            } label: {
                Label("Lernen (\(viewModel.dueFlashcards.count))", systemImage: "brain.head.profile")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.dueFlashcards.isEmpty)
        }
        .padding(.horizontal, Theme.Spacing.page)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let card = viewModel.currentReviewCard {
            VStack(spacing: 20) {
                HStack {
                    Text("Wiederholung")
                        .font(.headline)
                    Spacer()
                    Text("Noch \(viewModel.reviewQueue.count) Karten")
                        .foregroundStyle(Theme.textSecondary)
                    Button("Sitzung beenden") { viewModel.endReviewSession() }
                }
                .frame(maxWidth: 760)

                VStack(alignment: .leading, spacing: 18) {
                    Text("FRAGE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text(card.front)
                        .font(.system(size: 24, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    if viewModel.answerIsRevealed {
                        Divider()
                        Text("ANTWORT")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        ScrollView {
                            Text(card.back)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 220)
                        ratingButtons
                    } else {
                        Button("Antwort anzeigen") {
                            viewModel.revealAnswer()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.return, modifiers: [])
                        Text("Tipp: ↩ zeigt die Antwort, 1–4 bewertet sie.")
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(maxWidth: 760, minHeight: 280, alignment: .leading)
                .card(padding: 28, radius: 20)

                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.accent)
                Text("Wiederholung abgeschlossen")
                    .font(Theme.Typography.title)
                Text("Du hast alle Karten dieser Sitzung bearbeitet. Karten, die du noch einmal üben möchtest, werden erneut fällig.")
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
                HStack {
                    Button("Zur Kartenübersicht") { viewModel.endReviewSession() }
                    if !viewModel.dueFlashcards.isEmpty {
                        Button("Weitere fällige Karten lernen") { viewModel.startReviewSession() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
        }
    }

    private var ratingButtons: some View {
        HStack(spacing: 10) {
            ForEach(Array(FlashcardReviewRating.allCases.enumerated()), id: \.element) { index, rating in
                Button {
                    viewModel.rateCurrentCard(rating)
                } label: {
                    Label(rating.label, systemImage: rating.systemImage)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(rating.tint)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                .help("\(rating.label) (\(index + 1))")
            }
        }
        .padding(.top, 8)
    }

    private var cardList: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Karten durchsuchen …", text: $viewModel.cardSearchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                if !viewModel.dueFlashcards.isEmpty {
                    Text("Fällige Karten zuerst üben, bevor du neue Inhalte hinzufügst.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(18)

            if viewModel.flashcards.isEmpty {
                EmptyStateView(
                    title: "Noch keine Karteikarten",
                    systemImage: "rectangle.stack",
                    message: "Erstelle Fragen und Antworten selbst oder lege aus einer Notiz eine erste Karte an.",
                    actionTitle: "Erste Karte anlegen",
                    action: {
                        editingCard = nil
                        editorDraft = nil
                        isEditorPresented = true
                    }
                )
            } else {
                List {
                    ForEach(viewModel.visibleFlashcards) { card in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: card.isDue() ? "clock.badge.exclamationmark" : "calendar")
                                .foregroundStyle(card.isDue() ? Theme.accent : Theme.textSecondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(card.front)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(card.back)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(2)
                                HStack(spacing: 12) {
                                    if card.isDue() {
                                        Text("Fällig")
                                    } else {
                                        HStack(spacing: 3) {
                                            Text("Wiederholung")
                                            Text(card.dueAt, style: .relative)
                                        }
                                    }
                                    Text("\(card.repetitions) erfolgreiche Wiederholungen")
                                }
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Menu {
                                Button("Bearbeiten", systemImage: "pencil") {
                                    editingCard = card
                                    editorDraft = nil
                                    isEditorPresented = true
                                }
                                Button("Löschen", systemImage: "trash", role: .destructive) {
                                    pendingDeletion = card
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                            }
                            .menuStyle(.borderlessButton)
                        }
                        .padding(.vertical, 7)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private extension FlashcardReviewRating {
    var tint: Color {
        switch self {
        case .again: Theme.danger
        case .hard: Theme.warning
        case .good: Theme.accent
        case .easy: Theme.success
        }
    }
}
