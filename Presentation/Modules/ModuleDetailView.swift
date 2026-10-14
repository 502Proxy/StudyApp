import SwiftUI

/// Detail view for a module. Feature-specific state is kept in dedicated view models.
struct ModuleDetailView: View {
    let module: StudyModule

    @State private var section: DetailSection = .overview
    @State private var slidesViewModel: SlidesViewModel
    @State private var learningViewModel: LearningViewModel

    enum DetailSection: String, CaseIterable, Identifiable {
        case overview = "Übersicht"
        case slides = "Folien"
        case notes = "Notizen"
        case flashcards = "Karteikarten"
        case studySheets = "Lernzettel"

        var id: Self { self }
    }

    init(
        module: StudyModule,
        makeSlidesViewModel: SlidesViewModelFactory,
        makeLearningViewModel: LearningViewModelFactory
    ) {
        self.module = module
        _slidesViewModel = State(initialValue: makeSlidesViewModel(module.id))
        _learningViewModel = State(initialValue: makeLearningViewModel(module))
    }

    /// Während ein PDF geöffnet ist, bekommt der Viewer den ganzen Platz.
    private var isReading: Bool {
        section == .slides && slidesViewModel.openDocumentID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isReading {
                header
                    .padding(.horizontal, 32)
                    .padding(.top, 28)

                Picker("Bereich", selection: $section) {
                    ForEach(DetailSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 640)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
            }

            switch section {
            case .overview:
                overview
            case .slides:
                SlidesView(viewModel: slidesViewModel)
            case .notes:
                NotesOverviewView(viewModel: learningViewModel)
            case .flashcards:
                FlashcardsView(viewModel: learningViewModel)
            case .studySheets:
                StudySheetsView(viewModel: learningViewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .task {
            slidesViewModel.load()
            learningViewModel.load()
        }
        .alert(
            "Fehler",
            isPresented: Binding(
                get: { learningViewModel.errorMessage != nil || slidesViewModel.errorMessage != nil },
                set: {
                    if !$0 {
                        learningViewModel.errorMessage = nil
                        slidesViewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                learningViewModel.errorMessage = nil
                slidesViewModel.errorMessage = nil
            }
        } message: {
            Text(learningViewModel.errorMessage ?? slidesViewModel.errorMessage ?? "Unbekannter Fehler")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(module.color.color)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.name)
                    .font(Theme.Typography.largeTitle)
                    .foregroundStyle(Theme.textPrimary)
                if !module.code.isEmpty {
                    Text(module.code)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Dein Lernstand")
                    .font(Theme.Typography.title)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 14)], spacing: 14) {
                    SummaryCard(
                        title: "Foliensätze",
                        value: "\(slidesViewModel.documents.count)",
                        detail: "Importierte PDF-Dokumente",
                        icon: "doc.richtext"
                    ) {
                        section = .slides
                    }
                    SummaryCard(
                        title: "Notizen",
                        value: "\(learningViewModel.notes.count)",
                        detail: "Dokument- und Seitennotizen",
                        icon: "note.text"
                    ) {
                        section = .notes
                    }
                    SummaryCard(
                        title: "Karteikarten",
                        value: "\(learningViewModel.flashcards.count)",
                        detail: "\(learningViewModel.dueFlashcards.count) Wiederholungen fällig",
                        icon: "rectangle.stack"
                    ) {
                        section = .flashcards
                    }
                    SummaryCard(
                        title: "Lernzettel",
                        value: "\(learningViewModel.studySheets.count)",
                        detail: "Strukturierte Zusammenstellungen",
                        icon: "doc.text"
                    ) {
                        section = .studySheets
                    }
                }

                if !learningViewModel.dueFlashcards.isEmpty {
                    HStack(spacing: 14) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Zeit für die Wiederholung")
                                .font(.headline)
                            Text("\(learningViewModel.dueFlashcards.count) Karteikarten sind fällig. Kurze, regelmäßige Wiederholungen unterstützen langfristiges Behalten.")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Jetzt lernen") { section = .flashcards }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(18)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.surfaceBorder) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Empfohlener Ablauf")
                        .font(.headline)
                    Label("Notizen während des Lesens ergänzen.", systemImage: "1.circle")
                    Label("Wichtige Einträge für einen Lernzettel auswählen.", systemImage: "2.circle")
                    Label("Begriffe als Frage-Antwort-Karten festhalten und regelmäßig wiederholen.", systemImage: "3.circle")
                }
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(30)
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(value)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 125, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.surfaceBorder) }
        }
        .buttonStyle(.plain)
    }
}
