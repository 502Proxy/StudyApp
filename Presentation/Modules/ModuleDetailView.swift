import SwiftUI

/// Detail view for a module. Feature-specific state is kept in dedicated view models.
struct ModuleDetailView: View {
    let module: StudyModule
    /// Der geöffnete Bereich gehört `AppNavigation`, damit Kürzel, Verlauf und Sprünge aus anderen Bereichen greifen.
    @Binding var section: ModuleSection
    /// Einmaliger Auftrag (Folien fortsetzen, Notiz auswählen …), wird nach dem Ausführen geleert.
    @Binding var pendingIntent: ModuleIntent?
    /// Anstehende Kalendertermine, die mit diesem Modul verknüpft sind.
    let upcomingEvents: [StudyCalendarEvent]
    /// Termin dieses Moduls, der gerade läuft oder gleich beginnt.
    let liveEvent: StudyCalendarEvent?
    let liveProgress: Double
    /// Bezugszeit der Kalenderuhr, damit „läuft gerade“ überall gleich bewertet wird.
    let referenceDate: Date
    let onShowEvent: (StudyCalendarEvent) -> Void
    let onEdit: () -> Void

    @State private var slidesViewModel: SlidesViewModel
    @State private var learningViewModel: LearningViewModel

    init(
        module: StudyModule,
        section: Binding<ModuleSection>,
        pendingIntent: Binding<ModuleIntent?>,
        upcomingEvents: [StudyCalendarEvent],
        liveEvent: StudyCalendarEvent?,
        liveProgress: Double,
        referenceDate: Date,
        makeSlidesViewModel: SlidesViewModelFactory,
        makeLearningViewModel: LearningViewModelFactory,
        onShowEvent: @escaping (StudyCalendarEvent) -> Void,
        onEdit: @escaping () -> Void
    ) {
        self.module = module
        _section = section
        _pendingIntent = pendingIntent
        self.upcomingEvents = upcomingEvents
        self.liveEvent = liveEvent
        self.liveProgress = liveProgress
        self.referenceDate = referenceDate
        self.onShowEvent = onShowEvent
        self.onEdit = onEdit
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
                    .padding(.horizontal, Theme.Spacing.page)
                    .padding(.top, 22)
                    .padding(.bottom, 14)
            }

            Group {
                switch section {
                case .overview:
                    overview
                case .slides:
                    SlidesView(viewModel: slidesViewModel)
                case .notes:
                    NotesOverviewView(viewModel: learningViewModel) { note in
                        openInSlides(note)
                    }
                case .flashcards:
                    FlashcardsView(viewModel: learningViewModel)
                case .studySheets:
                    StudySheetsView(viewModel: learningViewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .navigationTitle(module.name)
        .task {
            slidesViewModel.load()
            learningViewModel.load()
            handle(pendingIntent)
        }
        .onChange(of: pendingIntent) { _, intent in
            handle(intent)
        }
        .onChange(of: section) { _, newSection in
            // Zahlen der Übersicht aktuell halten, z. B. nach dem Schreiben von Notizen im Reader.
            if newSection == .overview { learningViewModel.load() }
        }
        // Fehler der Folien zeigt `SlidesView` selbst an; hier nur die des Lernbereichs.
        .errorAlert(message: learningViewModel.errorMessage) { learningViewModel.errorMessage = nil }
    }

    // MARK: Aufträge

    private func handle(_ intent: ModuleIntent?) {
        guard let intent else { return }
        pendingIntent = nil
        switch intent {
        case .resumeSlides:
            if slidesViewModel.resumeReading() {
                section = .slides
            } else if section == .slides {
                section = .overview
            }
        case .openDocument(let id, let page):
            slidesViewModel.load()
            slidesViewModel.open(documentID: id, page: page)
            section = .slides
        case .selectNote(let id):
            learningViewModel.load()
            learningViewModel.noteSearchQuery = ""
            learningViewModel.selectedNoteID = id
            section = .notes
        case .lectureNote(let start, let title):
            learningViewModel.load()
            learningViewModel.openLectureNote(start: start, eventTitle: title)
            section = .notes
        }
    }

    private func openInSlides(_ note: LectureNote) {
        guard learningViewModel.document(for: note) != nil else { return }
        slidesViewModel.load()
        slidesViewModel.open(documentID: note.slideDocumentID, page: note.pageNumber)
        section = .slides
    }

    // MARK: Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ModuleBadge(name: module.name, color: module.color, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 10) {
                        Text(module.name)
                            .font(Theme.Typography.largeTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let liveEvent, liveEvent.startDate <= referenceDate {
                            LiveBadge()
                        }
                    }
                    if !module.code.isEmpty {
                        Text(module.code)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("Modul bearbeiten")
            }

            PillTabBar(
                items: ModuleSection.allCases,
                selection: $section,
                title: \.title,
                systemImage: \.systemImage
            )
        }
    }

    // MARK: Übersicht

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if let liveEvent {
                    LectureHeroCard(
                        event: liveEvent,
                        module: module,
                        isLive: liveEvent.startDate <= referenceDate,
                        progress: liveProgress,
                        referenceDate: referenceDate,
                        onOpenSlides: { pendingIntent = .resumeSlides },
                        onOpenNotes: { pendingIntent = .lectureNote(start: liveEvent.startDate, title: liveEvent.title) },
                        onOpenModule: { section = .slides }
                    )
                }

                if let resume = slidesViewModel.documentToResume {
                    resumeCard(resume)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 14) {
                    StatTile(
                        title: "Foliensätze",
                        value: "\(slidesViewModel.documents.count)",
                        detail: "Importierte PDF-Dokumente",
                        systemImage: "doc.richtext",
                        tint: module.color.color
                    ) { section = .slides }
                    StatTile(
                        title: "Notizen",
                        value: "\(learningViewModel.notes.count)",
                        detail: "Vorlesungs- und Seitennotizen",
                        systemImage: "note.text",
                        tint: Theme.accent
                    ) { section = .notes }
                    StatTile(
                        title: "Karteikarten",
                        value: "\(learningViewModel.flashcards.count)",
                        detail: "\(learningViewModel.dueFlashcards.count) Wiederholungen fällig",
                        systemImage: "rectangle.stack",
                        tint: Theme.warning
                    ) { section = .flashcards }
                    StatTile(
                        title: "Lernzettel",
                        value: "\(learningViewModel.studySheets.count)",
                        detail: "Zusammenstellungen",
                        systemImage: "doc.text",
                        tint: Theme.success
                    ) { section = .studySheets }
                }

                if !learningViewModel.dueFlashcards.isEmpty {
                    HStack(spacing: 16) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.warning)
                            .frame(width: 44, height: 44)
                            .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Zeit für die Wiederholung")
                                .font(Theme.Typography.headline)
                            Text("\(learningViewModel.dueFlashcards.count) Karteikarten sind fällig. Kurze, regelmäßige Wiederholungen wirken am besten.")
                                .font(Theme.Typography.small)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button("Jetzt lernen") {
                            section = .flashcards
                            learningViewModel.startReviewSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .card()
                }

                HStack(alignment: .top, spacing: 18) {
                    upcomingCard
                        .frame(maxWidth: .infinity)
                    quickActions
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.Spacing.page)
            .padding(.top, 6)
            .padding(.bottom, Theme.Spacing.page)
            .frame(maxWidth: 1120, alignment: .leading)
        }
    }

    private func resumeCard(_ document: SlideDocument) -> some View {
        Button {
            slidesViewModel.open(document)
            section = .slides
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "book.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(module.color.color)
                    .frame(width: 42, height: 42)
                    .background(module.color.softColor, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weiterlesen")
                        .font(Theme.Typography.overline)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.textSecondary)
                    Text(document.title)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    let page = slidesViewModel.lastPage(for: document) ?? 1
                    Text("Seite \(page) von \(document.pageCount)")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(module.color.color)
            }
            .card(padding: 14)
        }
        .buttonStyle(CardButtonStyle())
    }

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Nächste Termine", systemImage: "calendar")
            if upcomingEvents.isEmpty {
                Text("Keine anstehenden Termine verknüpft. Verknüpfe im Kalender einen Termin mit diesem Modul – alle Termine der Reihe folgen automatisch.")
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(upcomingEvents) { event in
                    Button {
                        onShowEvent(event)
                    } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(module.color.color)
                                .frame(width: 3, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.title)
                                    .font(Theme.Typography.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(event.location.isEmpty ? event.timeDescription() : "\(event.timeDescription()) · \(event.location)")
                                    .font(Theme.Typography.small)
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(event.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                                .font(Theme.Typography.small.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Im Kalender zeigen")
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Schnellzugriff", systemImage: "bolt")
            QuickActionRow(title: "Folien importieren", systemImage: "square.and.arrow.down") {
                section = .slides
                slidesViewModel.isImporterPresented = true
            }
            QuickActionRow(title: "Neue Notiz schreiben", systemImage: "square.and.pencil") {
                learningViewModel.load()
                learningViewModel.addModuleNote()
                section = .notes
            }
            QuickActionRow(title: "Karteikarten lernen", systemImage: "rectangle.stack") {
                section = .flashcards
            }
            QuickActionRow(title: "Lernzettel ansehen", systemImage: "doc.text") {
                section = .studySheets
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
    }
}

private struct QuickActionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
