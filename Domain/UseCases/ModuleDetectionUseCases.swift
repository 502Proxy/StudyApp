import Foundation

/// Eine im Kalender erkannte Lehrveranstaltung, die als Modul angelegt oder mit einem
/// bestehenden Modul verknüpft werden kann.
struct ModuleCandidate: Identifiable, Hashable, Sendable {
    var id: String { key }
    let key: String
    var name: String
    var code: String
    let kinds: [CourseEventKind]
    let eventIDs: [UUID]
    /// Termine ohne Modulzuordnung, die beim Übernehmen verknüpft werden.
    let unlinkedEventIDs: [UUID]
    let firstStart: Date
    let lastStart: Date
    /// Bestehendes Modul, zu dem die Veranstaltung gehört (über Name, Kürzel oder vorhandene Verknüpfungen).
    let existingModuleID: UUID?
    /// Mindestens ein Termin liegt im aktuellen Semesterfenster.
    let isCurrent: Bool
    /// Wiederkehrend oder eindeutig als Lehrveranstaltung benannt.
    let isLikelyCourse: Bool

    var occurrenceCount: Int { eventIDs.count }
}

struct ModuleDetectionResult: Equatable, Sendable {
    var createdModules: [StudyModule] = []
    var linkedEventCount = 0

    var isEmpty: Bool { createdModules.isEmpty && linkedEventCount == 0 }
}

/// Findet Lehrveranstaltungen im Kalender. Termine mit gleichem Fach (Vorlesung, Übung, Tutorium …)
/// werden zusammengefasst; Ganztägiges und sehr lange Termine (Ferien, Exkursionen) bleiben außen vor.
struct DetectModuleCandidatesUseCase: Sendable {
    /// Termine, deren Beginn so weit zurück- bzw. vorausliegt, zählen zum aktuellen Semester.
    var pastWindow: TimeInterval = 75 * 86_400
    var futureWindow: TimeInterval = 200 * 86_400
    var maximumDuration: TimeInterval = 8 * 3_600
    /// Ab so vielen Terminen im selben Wochenraster (Wochentag + Uhrzeit) gilt eine Reihe als Veranstaltung.
    var minimumWeeklySeries = 3
    var calendar: Calendar = .current

    func callAsFunction(
        events: [StudyCalendarEvent],
        modules: [StudyModule],
        now: Date = Date()
    ) -> [ModuleCandidate] {
        struct Group {
            var title: CourseTitle
            var events: [StudyCalendarEvent] = []
            var kinds = Set<CourseEventKind>()
            var codes: [String: Int] = [:]
            var names: [String: Int] = [:]
            var slots: [String: Int] = [:]
        }

        var groups: [String: Group] = [:]
        for event in events where !event.isAllDay && event.endDate.timeIntervalSince(event.startDate) <= maximumDuration {
            guard let title = CourseTitleAnalyzer.analyze(event.title) else { continue }
            var group = groups[title.key] ?? Group(title: title)
            group.events.append(event)
            let kind = title.kind == .other
                ? (CourseTitleAnalyzer.kind(inDescription: event.details) ?? .other)
                : title.kind
            group.kinds.insert(kind)
            let time = calendar.dateComponents([.weekday, .hour, .minute], from: event.startDate)
            group.slots["\(time.weekday ?? 0)-\(time.hour ?? 0):\(time.minute ?? 0)", default: 0] += 1
            if let code = title.code { group.codes[code, default: 0] += 1 }
            group.names[title.name, default: 0] += 1
            groups[title.key] = group
        }

        let moduleKeys = Dictionary(
            modules.map { (Self.moduleKey(for: $0), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let moduleCodes = Dictionary(
            modules.filter { !$0.code.isEmpty }.map { ($0.code.lowercased(), $0.id) },
            uniquingKeysWith: { first, _ in first }
        )
        let validModuleIDs = Set(modules.map(\.id))

        return groups.values.compactMap { group -> ModuleCandidate? in
            let sorted = group.events.sorted { $0.startDate < $1.startDate }
            guard let first = sorted.first, let last = sorted.last else { return nil }
            let code = group.codes.max { $0.value < $1.value }?.key ?? ""
            let name = group.names.max { lhs, rhs in
                lhs.value == rhs.value ? lhs.key.count > rhs.key.count : lhs.value < rhs.value
            }?.key ?? group.title.name

            // Die häufigste bestehende Verknüpfung gewinnt, danach Name und Kürzel.
            let linkedCounts = Dictionary(grouping: sorted.compactMap(\.moduleID).filter(validModuleIDs.contains), by: { $0 })
                .mapValues(\.count)
            let existing = linkedCounts.max { $0.value < $1.value }?.key
                ?? moduleKeys[group.title.key]
                ?? (code.isEmpty ? nil : moduleCodes[code.lowercased()])

            // Benannte Lehrveranstaltung oder eine regelmäßige Reihe im Wochenraster. Einzelne
            // private Termine (Arzt, Mensa) werden so nicht zu Modulen.
            let isWeeklySeries = (group.slots.values.max() ?? 0) >= minimumWeeklySeries
            let isLikelyCourse = group.kinds.contains(where: \.indicatesCourse) || isWeeklySeries
            let windowStart = now.addingTimeInterval(-pastWindow)
            let windowEnd = now.addingTimeInterval(futureWindow)
            let isCurrent = sorted.contains { $0.endDate >= windowStart && $0.startDate <= windowEnd }

            return ModuleCandidate(
                key: group.title.key,
                name: name,
                code: code,
                kinds: CourseEventKind.allCases.filter(group.kinds.contains),
                eventIDs: sorted.map(\.id),
                unlinkedEventIDs: sorted.filter { event in
                    event.moduleID.map { !validModuleIDs.contains($0) } ?? true
                }.map(\.id),
                firstStart: first.startDate,
                lastStart: last.startDate,
                existingModuleID: existing,
                isCurrent: isCurrent,
                isLikelyCourse: isLikelyCourse
            )
        }
        .sorted { lhs, rhs in
            if lhs.isCurrent != rhs.isCurrent { return lhs.isCurrent }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Schlüssel eines bestehenden Moduls, vergleichbar mit `CourseTitle.key`.
    static func moduleKey(for module: StudyModule) -> String {
        CourseTitleAnalyzer.analyze(module.name)?.key ?? CourseTitleAnalyzer.makeKey(module.name)
    }
}

/// Legt für ausgewählte Kandidaten Module an und verknüpft deren Termine.
/// Bereits manuell zugeordnete Termine werden nicht umgehängt.
@MainActor
struct ApplyModuleCandidatesUseCase {
    let moduleRepository: any ModuleRepository
    let calendarRepository: any StudyCalendarRepository
    var now: () -> Date = { Date() }

    @discardableResult
    func callAsFunction(_ candidates: [ModuleCandidate]) throws -> ModuleDetectionResult {
        var result = ModuleDetectionResult()
        var modules = try moduleRepository.all()
        let timestamp = now()

        for (offset, candidate) in candidates.enumerated() {
            let moduleID: UUID
            if let existing = candidate.existingModuleID, modules.contains(where: { $0.id == existing }) {
                moduleID = existing
            } else {
                let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let module = StudyModule(
                    id: UUID(),
                    name: name,
                    code: candidate.code.trimmingCharacters(in: .whitespacesAndNewlines),
                    color: Self.nextColor(for: modules),
                    // Kleiner Versatz, damit die Reihenfolge der Seitenleiste stabil bleibt.
                    createdAt: timestamp.addingTimeInterval(Double(offset) / 1_000)
                )
                try moduleRepository.add(module)
                modules.append(module)
                result.createdModules.append(module)
                moduleID = module.id
            }
            if !candidate.unlinkedEventIDs.isEmpty {
                try calendarRepository.updateModuleLinks(eventIDs: candidate.unlinkedEventIDs, moduleID: moduleID)
                result.linkedEventCount += candidate.unlinkedEventIDs.count
            }
        }
        return result
    }

    /// Die am seltensten genutzte Farbe, damit neue Module unterscheidbar bleiben.
    static func nextColor(for modules: [StudyModule]) -> ModuleColor {
        let usage = Dictionary(grouping: modules, by: \.color).mapValues(\.count)
        return ModuleColor.allCases.min { (usage[$0] ?? 0) < (usage[$1] ?? 0) } ?? .violet
    }
}

/// Automatischer Abgleich nach jedem Import: neue Lehrveranstaltungen werden als Modul angelegt,
/// neue Termine bekannter Fächer verknüpft. Abgelehnte Veranstaltungen (`ignoredKeys`) bleiben unberührt.
@MainActor
struct SyncModulesWithCalendarUseCase {
    let moduleRepository: any ModuleRepository
    let calendarRepository: any StudyCalendarRepository
    var detect = DetectModuleCandidatesUseCase()
    var now: () -> Date = { Date() }

    @discardableResult
    func callAsFunction(ignoredKeys: Set<String>, createModules: Bool = true) throws -> ModuleDetectionResult {
        let candidates = detect(
            events: try calendarRepository.events(),
            modules: try moduleRepository.all(),
            now: now()
        )
        let selected = candidates.filter { candidate in
            guard !ignoredKeys.contains(candidate.key) else { return false }
            if candidate.existingModuleID != nil { return !candidate.unlinkedEventIDs.isEmpty }
            return createModules && candidate.isLikelyCourse && candidate.isCurrent
        }
        guard !selected.isEmpty else { return ModuleDetectionResult() }
        return try ApplyModuleCandidatesUseCase(
            moduleRepository: moduleRepository,
            calendarRepository: calendarRepository,
            now: now
        )(selected)
    }
}

// MARK: - Laufende Vorlesung

enum LectureSchedule {
    /// Termin eines Moduls, der gerade läuft oder in Kürze (`leadTime`) beginnt.
    /// Bei Überschneidungen gewinnt der zuletzt begonnene Termin.
    static func current(
        in events: [StudyCalendarEvent],
        at now: Date,
        leadTime: TimeInterval = 10 * 60
    ) -> StudyCalendarEvent? {
        events
            .filter { $0.moduleID != nil && !$0.isAllDay }
            .filter { $0.startDate.addingTimeInterval(-leadTime) <= now && now < $0.endDate }
            .max { lhs, rhs in
                lhs.startDate == rhs.startDate ? lhs.endDate > rhs.endDate : lhs.startDate < rhs.startDate
            }
    }

    /// Nächster noch nicht begonnener Termin (optional nur mit Modul).
    static func next(
        in events: [StudyCalendarEvent],
        after now: Date,
        linkedOnly: Bool = true
    ) -> StudyCalendarEvent? {
        events
            .filter { (!linkedOnly || $0.moduleID != nil) && !$0.isAllDay && $0.startDate > now }
            .min { $0.startDate < $1.startDate }
    }
}
