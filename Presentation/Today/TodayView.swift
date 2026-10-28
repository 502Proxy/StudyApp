import SwiftUI

/// Startseite: was jetzt ansteht, was heute noch kommt und was wiederholt werden sollte.
struct TodayView: View {
    @Bindable var calendar: StudyCalendarViewModel
    @Bindable var today: TodayViewModel
    @Bindable var assignments: AssignmentsViewModel
    @Bindable var exams: ExamsViewModel
    let onOpenModule: (UUID, ModuleSection, ModuleIntent?) -> Void
    let onShowCalendar: () -> Void
    let onCreateModule: () -> Void
    let onCreateLectureNote: (StudyCalendarEvent) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                header
                // Two columns on wide windows, one column when the window is narrow.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Self.columnSpacing) {
                        primaryColumn
                            .frame(minWidth: 460, maxWidth: .infinity)
                        secondaryColumn
                            .frame(minWidth: 320, maxWidth: 440)
                    }
                    VStack(spacing: Self.columnSpacing) {
                        primaryColumn
                        secondaryColumn
                    }
                }
            }
            .padding(Theme.Spacing.page)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Heute")
        .task {
            today.load()
            exams.load()
        }
    }

    private static let columnSpacing: CGFloat = 20

    /// What is happening now: the running or next lecture, today's timeline and recent notes.
    private var primaryColumn: some View {
        VStack(alignment: .leading, spacing: Self.columnSpacing) {
            hero
            scheduleCard
            if !today.recentNotes.isEmpty {
                recentNotes
            }
        }
    }

    /// What needs attention: assignments, flashcards and exams.
    private var secondaryColumn: some View {
        VStack(alignment: .leading, spacing: Self.columnSpacing) {
            assignmentsCard
            reviewCard
            if !exams.upcoming.isEmpty {
                UpcomingExamsCard(exams: exams.upcoming) { overview in
                    onOpenModule(overview.module.id, .exam, nil)
                }
            }
        }
    }

    // MARK: Header

    /// Date as the title and one line with what is due, instead of a greeting and a row of pills.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(calendar.referenceDate, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.textPrimary)
            if !summary.isEmpty {
                Text(summary)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var summary: String {
        var parts = [StudyCalendarViewModel.eventCountText(calendar.todayEvents.count) + " heute"]
        let dueThisWeek = assignments.upcoming(days: 7).count
        if dueThisWeek > 0 {
            parts.append(dueThisWeek == 1 ? "1 Abgabe diese Woche" : "\(dueThisWeek) Abgaben diese Woche")
        }
        if assignments.overdueCount > 0 {
            parts.append("\(assignments.overdueCount) überfällig")
        }
        if today.totalDue > 0 {
            parts.append("\(today.totalDue) Karten fällig")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Jetzt / Als Nächstes

    @ViewBuilder
    private var hero: some View {
        if let event = calendar.currentLecture, let module = calendar.module(for: event) {
            LectureHeroCard(
                event: event,
                module: module,
                isLive: event.startDate <= calendar.referenceDate,
                progress: calendar.progress(of: event),
                referenceDate: calendar.referenceDate,
                onOpenSlides: { onOpenModule(module.id, .slides, .resumeSlides) },
                onOpenNotes: { onCreateLectureNote(event) },
                onOpenModule: { onOpenModule(module.id, .overview, nil) }
            )
        } else if let event = calendar.nextLecture, let module = calendar.module(for: event) {
            LectureHeroCard(
                event: event,
                module: module,
                isLive: false,
                progress: 0,
                referenceDate: calendar.referenceDate,
                onOpenSlides: { onOpenModule(module.id, .slides, .resumeSlides) },
                onOpenNotes: { onCreateLectureNote(event) },
                onOpenModule: { onOpenModule(module.id, .overview, nil) }
            )
        } else if calendar.isEmpty {
            onboardingCard
        }
    }

    private var onboardingCard: some View {
        HStack(alignment: .center, spacing: 20) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Theme.accentText)
                .frame(width: 64, height: 64)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("Stundenplan verbinden")
                    .font(Theme.Typography.title)
                Text("Importiere deinen Stundenplan als .ics-Datei oder abonniere den Kalender-Link aus Stud.IP, HISinOne oder Moodle. StudyApp legt daraus automatisch deine Module an und öffnet in der Vorlesung direkt die passenden Folien.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 8) {
                Button("Stundenplan hinzufügen", action: onShowCalendar)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Modul manuell anlegen", action: onCreateModule)
                    .buttonStyle(.link)
            }
        }
        .card(padding: 22)
    }

    // MARK: Heute

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Heute", systemImage: "clock") {
                Button("Kalender", action: onShowCalendar)
                    .buttonStyle(.link)
                    .font(Theme.Typography.small)
            }
            let events = calendar.todayEvents
            if events.isEmpty {
                Text("Keine Termine mehr – Zeit zum Wiederholen.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 2) {
                    ForEach(events) { event in
                        TimelineRow(
                            event: event,
                            module: calendar.module(for: event),
                            isLive: calendar.currentLecture?.id == event.id && event.startDate <= calendar.referenceDate,
                            isPast: event.endDate <= calendar.referenceDate
                        ) {
                            if let moduleID = event.moduleID {
                                onOpenModule(moduleID, .overview, nil)
                            } else {
                                onShowCalendar()
                                calendar.reveal(event)
                                calendar.selectedEvent = event
                            }
                        }
                    }
                }
            }
        }
        .card()
    }

    // MARK: Abgaben

    private var assignmentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Abgaben", systemImage: "checklist") {
                Button {
                    assignments.startNewAssignment(moduleID: nil)
                } label: {
                    Label("Neu", systemImage: "plus")
                }
                .buttonStyle(.link)
                .font(Theme.Typography.small)
                .disabled(today.modules.isEmpty)
            }
            let upcoming = assignments.upcoming(days: 7)
            if upcoming.isEmpty {
                Text("Keine Abgaben in den nächsten 7 Tagen.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                VStack(spacing: 0) {
                    ForEach(upcoming.prefix(6)) { assignment in
                        AssignmentRow(
                            assignment: assignment,
                            urgency: assignments.urgency(of: assignment),
                            dueText: assignments.dueText(for: assignment),
                            module: today.module(withID: assignment.moduleID),
                            onToggle: { assignments.setCompleted(assignment, !assignment.isCompleted) },
                            onEdit: { assignments.edit(assignment) },
                            onDelete: { assignments.delete(assignment) }
                        )
                    }
                }
                if upcoming.count > 6 {
                    Text("+ \(upcoming.count - 6) weitere")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .card()
        .task { assignments.load() }
    }

    // MARK: Wiederholen

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Wiederholen", systemImage: "brain.head.profile")
            let modules = today.modules
                .filter { (today.dueCounts[$0.id] ?? 0) > 0 }
                .sorted { (today.dueCounts[$0.id] ?? 0) > (today.dueCounts[$1.id] ?? 0) }
            if let first = modules.first {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(today.totalDue)")
                                .font(Theme.Typography.metric)
                                .foregroundStyle(Theme.textPrimary)
                            Text(today.totalDue == 1 ? "Karte fällig" : "Karten fällig")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(modules.map { "\($0.name) \(today.dueCounts[$0.id] ?? 0)" }.joined(separator: " · "))
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    // Starts with the module that has the most due cards.
                    Button("Lernen starten") { onOpenModule(first.id, .flashcards, nil) }
                        .buttonStyle(.borderedProminent)
                        .help("Karteikarten von „\(first.name)“ wiederholen")
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.success)
                    Text(today.cardCounts.values.reduce(0, +) == 0 ? "Noch keine Karteikarten angelegt." : "Alles wiederholt. Stark!")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .card()
    }

    // MARK: Notizen

    private var recentNotes: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader("Zuletzt bearbeitet", systemImage: "note.text")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                ForEach(today.recentNotes) { reference in
                    Button {
                        onOpenModule(reference.module.id, .notes, .selectNote(reference.note.id))
                    } label: {
                        NoteReferenceCard(reference: reference)
                    }
                    .buttonStyle(CardButtonStyle())
                }
            }
        }
    }
}

// MARK: - Bausteine

/// Große Karte für die laufende oder nächste Vorlesung mit direkten Aktionen.
struct LectureHeroCard: View {
    let event: StudyCalendarEvent
    let module: StudyModule
    let isLive: Bool
    let progress: Double
    let referenceDate: Date
    let onOpenSlides: () -> Void
    let onOpenNotes: () -> Void
    let onOpenModule: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if isLive {
                    LiveBadge(text: "LÄUFT GERADE")
                } else {
                    Pill(text: Self.relativeStart(event.startDate, from: referenceDate), systemImage: "clock", tint: module.color.color)
                }
                Spacer()
                Button(action: onOpenModule) {
                    Label("Zum Modul", systemImage: "arrow.up.right")
                        .font(Theme.Typography.small.weight(.medium))
                }
                .buttonStyle(.link)
            }

            HStack(alignment: .top, spacing: 16) {
                ModuleBadge(name: module.name, color: module.color, size: 52)
                VStack(alignment: .leading, spacing: 5) {
                    Text(module.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if event.title != module.name {
                        Text(event.title)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 14) {
                        Label(event.timeDescription(), systemImage: "clock")
                        if !event.location.isEmpty {
                            Label(event.location, systemImage: "mappin.and.ellipse")
                                .lineLimit(1)
                        }
                    }
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if isLive {
                VStack(alignment: .leading, spacing: 6) {
                    SlimProgressBar(progress: progress, tint: module.color.color)
                    Text("noch \(Self.durationText(event.endDate.timeIntervalSince(referenceDate)))")
                        .font(Theme.Typography.small)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: onOpenSlides) {
                    Label("Folien öffnen", systemImage: "doc.richtext")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .tint(module.color.color)
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)

                Button(action: onOpenNotes) {
                    Label("Vorlesungsnotiz", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .fill(Theme.surface)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(module.color.color.opacity(0.10))
                        .frame(width: 260, height: 260)
                        .blur(radius: 40)
                        .offset(x: 60, y: -90)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(isLive ? module.color.color.opacity(0.45) : Theme.surfaceBorder, lineWidth: isLive ? 1.5 : 1)
        }
        .shadow(color: Theme.shadow.opacity(0.06), radius: 14, y: 4)
    }

    static func relativeStart(_ start: Date, from reference: Date, calendar: Calendar = .current) -> String {
        let interval = start.timeIntervalSince(reference)
        if interval <= 0 { return "beginnt jetzt" }
        if calendar.isDate(start, inSameDayAs: reference) {
            return "in \(durationText(interval))"
        }
        let time = start.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInTomorrow(start) { return "morgen, \(time)" }
        return start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", \(time)"
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes) Min." }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) Std." : "\(hours) Std. \(rest) Min."
    }
}

/// Eine Zeile im Tagesplan.
private struct TimelineRow: View {
    let event: StudyCalendarEvent
    let module: StudyModule?
    let isLive: Bool
    let isPast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(event.isAllDay ? "ganztags" : event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isPast ? Theme.textTertiary : Theme.textPrimary)
                    if !event.isAllDay {
                        Text(event.endDate.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 54, alignment: .trailing)

                RoundedRectangle(cornerRadius: 2)
                    .fill(module?.color.color ?? Theme.textTertiary)
                    .frame(width: 3)
                    .opacity(isPast ? 0.4 : 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(module?.name ?? event.title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(isPast ? Theme.textSecondary : Theme.textPrimary)
                            .lineLimit(1)
                        if isLive { LiveBadge() }
                    }
                    let subtitle = [module == nil ? nil : event.title, event.location.isEmpty ? nil : event.location]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Typography.small)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(isLive ? (module?.color.softColor ?? Theme.accentSoft) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kachel einer Notiz mit Herkunft und Ausschnitt.
struct NoteReferenceCard: View {
    let reference: NoteReference

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ModuleBadge(name: reference.module.name, color: reference.module.color, size: 22)
                Text(reference.module.name)
                    .font(Theme.Typography.small.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(reference.note.updatedAt, format: .relative(presentation: .named))
                    .font(Theme.Typography.small)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(reference.displayTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(reference.snippet.isEmpty ? "Leere Notiz" : reference.snippet)
                .font(Theme.Typography.small)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2, reservesSpace: true)
            if !reference.isModuleNote {
                Label(reference.locationLabel, systemImage: "doc.richtext")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }
}
