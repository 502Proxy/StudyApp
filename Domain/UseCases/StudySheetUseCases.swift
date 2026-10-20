import Foundation

@MainActor
struct ListStudySheetsUseCase {
    let repository: any StudySheetRepository

    func callAsFunction(moduleID: UUID) throws -> [StudySheet] {
        try repository.sheets(forModule: moduleID).sorted { $0.updatedAt > $1.updatedAt }
    }
}

/// Builds a usable study sheet without external services: note content remains intact,
/// Markdown headings become an outline, and self-check prompts are added for active recall.
struct StudySheetContentBuilder: Sendable {
    func build(title: String, notes: [LectureNote]) -> String {
        let orderedNotes = notes.sorted(by: noteOrder)
        let topicLines = orderedNotes.map { note in
            let page = note.pageNumber.map { " (Seite \($0))" } ?? " (Gesamtdokument)"
            return "- **\(note.title)**\(page)"
        }

        let extractedHeadings = orderedNotes.flatMap { note in
            note.content
                .components(separatedBy: .newlines)
                .compactMap { line -> String? in
                    let cleaned = line.trimmingCharacters(in: .whitespaces)
                    guard cleaned.hasPrefix("#") else { return nil }
                    let heading = cleaned.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                    return heading.isEmpty ? nil : heading
                }
        }

        var sections = [
            "# \(title)",
            "> Erstellt aus \(orderedNotes.count) ausgewählten Notizen. Die Originalinhalte bleiben erhalten; die Übersicht und Selbstkontrollfragen werden automatisch ergänzt.",
            "## Themenübersicht",
            topicLines.joined(separator: "\n")
        ]

        if !extractedHeadings.isEmpty {
            sections.append("## Begriffe und Zwischenüberschriften\n\n" + extractedHeadings.map { "- \($0)" }.joined(separator: "\n"))
        }

        let noteSections = orderedNotes.map { note -> String in
            let source = note.pageNumber.map { "Seite \($0)" } ?? "Gesamtdokument"
            let heading = "### \(note.title) – \(source)"
            let body = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? heading : "\(heading)\n\n\(body)"
        }
        sections.append("## Zusammengeführte Notizen\n\n" + noteSections.joined(separator: "\n\n---\n\n"))

        let questions = orderedNotes.map { note -> String in
            let page = note.pageNumber.map { " (Seite \($0))" } ?? ""
            return "- Welche Kernaussagen enthält **\(note.title)**\(page)?"
        }
        sections.append("## Selbstkontrolle\n\nDecke die Notizen ab und beantworte die Fragen aus dem Gedächtnis.\n\n" + questions.joined(separator: "\n"))
        return sections.joined(separator: "\n\n") + "\n"
    }

    private func noteOrder(_ lhs: LectureNote, _ rhs: LectureNote) -> Bool {
        switch (lhs.pageNumber, rhs.pageNumber) {
        case (nil, nil): return lhs.updatedAt < rhs.updatedAt
        case (nil, _?): return true
        case (_?, nil): return false
        case let (left?, right?): return left == right ? lhs.updatedAt < rhs.updatedAt : left < right
        }
    }
}

@MainActor
struct CreateStudySheetUseCase {
    let repository: any StudySheetRepository
    var now: () -> Date = { Date() }
    var contentBuilder = StudySheetContentBuilder()

    @discardableResult
    func callAsFunction(moduleID: UUID, title: String, notes: [LectureNote]) throws -> StudySheet {
        let cleanTitle = title.trimmed
        guard !cleanTitle.isEmpty else { throw StudySheetError.emptyTitle }
        let uniqueNotes = Dictionary(grouping: notes, by: \.id).compactMap { $0.value.first }
        guard !uniqueNotes.isEmpty else { throw StudySheetError.noSourceNotes }

        let timestamp = now()
        let sheet = StudySheet(
            moduleID: moduleID,
            title: cleanTitle,
            content: contentBuilder.build(title: cleanTitle, notes: uniqueNotes),
            sourceNoteIDs: uniqueNotes.map(\.id),
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try repository.add(sheet)
        return sheet
    }
}

@MainActor
struct DeleteStudySheetUseCase {
    let repository: any StudySheetRepository

    func callAsFunction(id: UUID) throws {
        try repository.delete(id: id)
    }
}
