import AppKit
import Observation
internal import PDFKit
import SwiftUI

/// Hält die Observer-Tokens und entfernt sie beim Freigeben.
/// Eigene Klasse, weil `deinit` eines MainActor-Typs nicht auf dessen Eigenschaften zugreifen soll.
private final class ObserverBag: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// Steuert eine `PDFView`: Seitenwechsel, Zoom und alle Markierungswerkzeuge.
/// Markierungen sind echte PDF-Annotationen; gespeichert wird über `save`, nicht direkt ins Dateisystem.
@MainActor
@Observable
final class PDFReaderController {
    let pdfView = AnnotatingPDFView()
    private(set) var pageIndex = 0
    private(set) var pageCount = 0
    private(set) var hasSelection = false
    private(set) var isLoaded = false
    var errorMessage: String?

    private(set) var tool: AnnotationTool = .select
    /// Zuletzt gewählte Farbe je Werkzeug, damit Textmarker gelb und Stift rot bleiben können.
    private var toolColors: [AnnotationTool: AnnotationColor] = [:]
    var penWidth: PenWidth = .medium

    var color: AnnotationColor {
        get { toolColors[tool] ?? AnnotationColor.defaultColor(for: tool) }
        set { toolColors[tool] = newValue }
    }
    private(set) var canUndo = false
    /// Steigt bei jeder Änderung, damit die Markierungsliste neu berechnet wird.
    private(set) var annotationRevision = 0

    /// Suchtreffer im Dokument, in Lesereihenfolge.
    private(set) var searchResults: [SearchResult] = []
    /// Index des hervorgehobenen Treffers in `searchResults`.
    private(set) var currentSearchIndex: Int?
    private(set) var searchedText = ""
    @ObservationIgnored private var searchSelections: [PDFSelection] = []

    struct SearchResult: Identifiable {
        let id: Int
        let pageNumber: Int
        /// Umgebender Text mit dem Treffer, für die Trefferliste.
        let context: String
    }
    /// Ort für ein neues Textfeld; die Ansicht fragt daraufhin den Text ab.
    var pendingTextLocation: PendingText?

    struct PendingText: Identifiable {
        let id = UUID()
        let pageIndex: Int
        let point: CGPoint
    }

    /// Eine rückgängig machbare Aktion, z. B. eine Markierung über mehrere Zeilen.
    private enum Change {
        case added(PDFAnnotation, PDFPage)
        case removed(PDFAnnotation, PDFPage)
    }

    private let document: PDFDocument?
    private let save: (Data) throws -> Void
    private let observers = ObserverBag()
    @ObservationIgnored private var undoStack: [[Change]] = []
    @ObservationIgnored private var activeStroke: (page: PDFPage, points: [CGPoint], annotation: PDFAnnotation, path: NSBezierPath)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var hasUnsavedChanges = false

    private static let undoLimit = 50
    private static let saveDelay: Duration = .milliseconds(800)

    /// - Parameter save: Schreibt die PDF-Daten zurück (über den `FileStorage`-Port).
    init(fileURL: URL, save: @escaping (Data) throws -> Void) {
        self.save = save
        // Aus dem Speicher laden statt von der Datei, damit das spätere Zurückschreiben sicher ist.
        if let data = try? Data(contentsOf: fileURL), let loaded = PDFDocument(data: data) {
            document = loaded
        } else {
            document = nil
        }
        configure()
    }

    // MARK: Aufbau

    private func configure() {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.displaysPageBreaks = true
        pdfView.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: 0x141519) : NSColor(hex: 0xECEEF4)
        }
        pdfView.document = document

        pageCount = document?.pageCount ?? 0
        isLoaded = document != nil

        pdfView.onSelectionFinished = { [weak self] in self?.selectionFinished() }
        pdfView.onStrokeBegan = { [weak self] page, point in self?.beginStroke(on: page, at: point) }
        pdfView.onStrokeMoved = { [weak self] point in self?.continueStroke(to: point) }
        pdfView.onStrokeEnded = { [weak self] in self?.endStroke() }
        pdfView.onPageClick = { [weak self] page, point in self?.handleClick(on: page, at: point) }

        let center = NotificationCenter.default
        observers.add(
            center.addObserver(forName: .PDFViewPageChanged, object: pdfView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncPage() }
            }
        )
        observers.add(
            center.addObserver(forName: .PDFViewSelectionChanged, object: pdfView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncSelection() }
            }
        )
    }

    private func syncPage() {
        guard let document, let page = pdfView.currentPage else { return }
        pageIndex = document.index(for: page)
    }

    private func syncSelection() {
        hasSelection = pdfView.currentSelection?.string?.isEmpty == false
    }

    /// Markierter Text, z. B. zum Übernehmen in die Notizen.
    var selectedText: String? {
        let text = pdfView.currentSelection?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    // MARK: Navigation und Zoom

    func goToPreviousPage() {
        pdfView.goToPreviousPage(nil)
    }

    func goToNextPage() {
        pdfView.goToNextPage(nil)
    }

    /// Navigates to a 1-based page number, used when opening a per-page note from search.
    func goToPage(number: Int) {
        guard let document,
              number >= 1,
              number <= document.pageCount,
              let page = document.page(at: number - 1) else { return }
        pdfView.go(to: page)
        syncPage()
    }

    func zoomIn() {
        pdfView.zoomIn(nil)
    }

    func zoomOut() {
        pdfView.zoomOut(nil)
    }

    func zoomToFit() {
        pdfView.autoScales = true
    }

    // MARK: Suche

    /// Sucht `query` im ganzen Dokument (ohne Groß-/Kleinschreibung und Akzente),
    /// markiert alle Treffer und springt zum ersten Treffer ab der aktuellen Seite.
    func search(_ query: String) {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != searchedText else { return }
        searchedText = text
        guard !text.isEmpty, let document else {
            clearSearch()
            return
        }

        searchSelections = document.findString(text, withOptions: [.caseInsensitive, .diacriticInsensitive])
        searchResults = searchSelections.enumerated().map { index, selection in
            let page = selection.pages.first.map { document.index(for: $0) + 1 } ?? 1
            return SearchResult(id: index, pageNumber: page, context: Self.context(of: selection))
        }
        for selection in searchSelections {
            selection.color = NSColor.systemYellow.withAlphaComponent(0.55)
        }
        pdfView.highlightedSelections = searchSelections

        let start = searchResults.firstIndex { $0.pageNumber >= pageIndex + 1 } ?? 0
        showSearchResult(at: searchResults.isEmpty ? nil : start)
    }

    func nextSearchResult() {
        guard !searchResults.isEmpty else { return }
        showSearchResult(at: ((currentSearchIndex ?? -1) + 1) % searchResults.count)
    }

    func previousSearchResult() {
        guard !searchResults.isEmpty else { return }
        let count = searchResults.count
        showSearchResult(at: ((currentSearchIndex ?? 0) - 1 + count) % count)
    }

    func showSearchResult(at index: Int?) {
        currentSearchIndex = index
        guard let index, searchSelections.indices.contains(index) else { return }
        let selection = searchSelections[index]
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.scrollSelectionToVisible(nil)
        syncPage()
    }

    func clearSearch() {
        searchedText = ""
        searchSelections = []
        searchResults = []
        currentSearchIndex = nil
        pdfView.highlightedSelections = nil
        pdfView.clearSelection()
    }

    /// Etwas Text vor und nach dem Treffer, auf eine Zeile reduziert.
    private static func context(of selection: PDFSelection) -> String {
        guard let context = selection.copy() as? PDFSelection else { return selection.string ?? "" }
        context.extend(atStart: 40)
        context.extend(atEnd: 60)
        return (context.string ?? selection.string ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: Werkzeuge

    func select(_ tool: AnnotationTool) {
        self.tool = tool
        pdfView.interaction = tool.interaction
        // Eine bestehende Auswahl wird mit dem neuen Markup-Werkzeug sofort markiert.
        if tool.markupSubtype != nil, hasSelection {
            applyMarkupToSelection()
        }
    }

    private func selectionFinished() {
        guard tool.markupSubtype != nil, hasSelection else { return }
        applyMarkupToSelection()
    }

    // MARK: Textmarkierungen

    /// Markiert die aktuelle Auswahl mit dem gewählten Werkzeug (Textmarker, Unter- oder Durchstreichen).
    func applyMarkupToSelection(using subtype: PDFAnnotationSubtype? = nil) {
        let subtype = subtype ?? tool.markupSubtype ?? .highlight
        guard let selection = pdfView.currentSelection else { return }
        var changes: [Change] = []

        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { continue }

                let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
                annotation.color = subtype == .highlight ? color.nsColor.withAlphaComponent(0.45) : color.nsColor
                // Eckpunkte relativ zu `bounds`, damit auch andere PDF-Programme die Markierung zeichnen.
                let width = bounds.width
                let height = bounds.height
                annotation.quadrilateralPoints = [
                    NSValue(point: CGPoint(x: 0, y: height)),
                    NSValue(point: CGPoint(x: width, y: height)),
                    NSValue(point: CGPoint(x: 0, y: 0)),
                    NSValue(point: CGPoint(x: width, y: 0)),
                ]
                page.addAnnotation(annotation)
                changes.append(.added(annotation, page))
            }
        }

        pdfView.clearSelection()
        hasSelection = false
        record(changes)
    }

    /// Entfernt alle Markierungen (Textmarker, Unter-/Durchstreichen), die die Auswahl überdecken.
    func removeMarkupInSelection() {
        guard let selection = pdfView.currentSelection else { return }
        var changes: [Change] = []

        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                for annotation in page.annotations where Self.isMarkup(annotation) {
                    let overlap = annotation.bounds.intersection(bounds)
                    // Nur Markierungen entfernen, die diese Zeile wirklich überdecken.
                    if !overlap.isNull, overlap.width > 1, overlap.height > bounds.height * 0.5 {
                        page.removeAnnotation(annotation)
                        changes.append(.removed(annotation, page))
                    }
                }
            }
        }

        pdfView.clearSelection()
        hasSelection = false
        record(changes)
    }

    // MARK: Stift

    private func beginStroke(on page: PDFPage, at point: CGPoint) {
        let pageBounds = page.bounds(for: .mediaBox)
        let annotation = PDFAnnotation(bounds: pageBounds, forType: .ink, withProperties: nil)
        annotation.color = color.nsColor
        annotation.border = Self.border(width: penWidth.rawValue)
        let path = Self.path(through: [point], offset: pageBounds.origin, width: penWidth.rawValue)
        annotation.add(path)
        page.addAnnotation(annotation)
        activeStroke = (page, [point], annotation, path)
    }

    private func continueStroke(to point: CGPoint) {
        guard var stroke = activeStroke else { return }
        // Sehr dichte Punkte bringen nichts und machen die Datei nur größer.
        if let last = stroke.points.last, hypot(point.x - last.x, point.y - last.y) < 0.8 { return }
        stroke.points.append(point)
        let path = Self.path(through: stroke.points, offset: stroke.page.bounds(for: .mediaBox).origin, width: penWidth.rawValue)
        stroke.annotation.remove(stroke.path)
        stroke.annotation.add(path)
        stroke.path = path
        activeStroke = stroke
        pdfView.annotationsChanged(on: stroke.page)
    }

    /// Ersetzt die seitengroße Vorschau durch eine Annotation mit passenden Grenzen,
    /// damit der Radierer nur diesen Strich trifft.
    private func endStroke() {
        guard let stroke = activeStroke else { return }
        activeStroke = nil
        stroke.page.removeAnnotation(stroke.annotation)

        let inset = -max(penWidth.rawValue * 2, 4)
        let xs = stroke.points.map(\.x)
        let ys = stroke.points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).insetBy(dx: inset, dy: inset)

        let annotation = PDFAnnotation(bounds: bounds, forType: .ink, withProperties: nil)
        annotation.color = color.nsColor
        annotation.border = Self.border(width: penWidth.rawValue)
        annotation.add(Self.path(through: stroke.points, offset: bounds.origin, width: penWidth.rawValue))
        stroke.page.addAnnotation(annotation)
        record([.added(annotation, stroke.page)])
    }

    private static func path(through points: [CGPoint], offset: CGPoint, width: Double) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = width
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        let shifted = points.map { CGPoint(x: $0.x - offset.x, y: $0.y - offset.y) }
        guard let first = shifted.first else { return path }
        path.move(to: first)
        if shifted.count == 1 {
            // Ein einzelner Klick ergibt einen Punkt.
            path.line(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1))
        }
        for point in shifted.dropFirst() {
            path.line(to: point)
        }
        return path
    }

    private static func border(width: Double) -> PDFBorder {
        let border = PDFBorder()
        border.lineWidth = width
        return border
    }

    // MARK: Textfelder und Radierer

    private func handleClick(on page: PDFPage, at point: CGPoint) {
        switch tool {
        case .text:
            guard let document else { return }
            pendingTextLocation = PendingText(pageIndex: document.index(for: page), point: point)
        case .eraser:
            erase(on: page, at: point)
        default:
            break
        }
    }

    /// Setzt ein Textfeld an die zuvor angeklickte Stelle.
    func addText(_ text: String, at location: PendingText) {
        pendingTextLocation = nil
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, let page = document?.page(at: location.pageIndex) else { return }

        let font = NSFont.systemFont(ofSize: 12)
        let size = (content as NSString).boundingRect(
            with: CGSize(width: 220, height: 1_000),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font],
            context: nil
        ).size
        let bounds = CGRect(
            x: location.point.x,
            y: location.point.y - size.height - 8,
            width: ceil(size.width) + 12,
            height: ceil(size.height) + 8
        )
        let annotation = PDFAnnotation(bounds: bounds, forType: .freeText, withProperties: nil)
        annotation.contents = content
        annotation.font = font
        annotation.fontColor = NSColor(hex: 0x111827)
        annotation.color = color.nsColor.withAlphaComponent(0.35)
        annotation.alignment = .left
        page.addAnnotation(annotation)
        record([.added(annotation, page)])
    }

    private func erase(on page: PDFPage, at point: CGPoint) {
        guard let annotation = page.annotations.reversed().first(where: { annotation in
            Self.isUserAnnotation(annotation) && annotation.bounds.insetBy(dx: -3, dy: -3).contains(point)
        }) else { return }
        page.removeAnnotation(annotation)
        record([.removed(annotation, page)])
    }

    // MARK: Rückgängig

    func undo() {
        guard let changes = undoStack.popLast() else { return }
        for change in changes.reversed() {
            switch change {
            case .added(let annotation, let page): page.removeAnnotation(annotation)
            case .removed(let annotation, let page): page.addAnnotation(annotation)
            }
        }
        canUndo = !undoStack.isEmpty
        annotationRevision += 1
        scheduleSave()
    }

    private func record(_ changes: [Change]) {
        guard !changes.isEmpty else { return }
        undoStack.append(changes)
        if undoStack.count > Self.undoLimit { undoStack.removeFirst() }
        canUndo = true
        annotationRevision += 1
        scheduleSave()
    }

    // MARK: Übersicht

    /// Alle eigenen Markierungen in Seitenreihenfolge, mit dem markierten Text als Vorschau.
    func annotationSummaries() -> [AnnotationSummary] {
        guard let document else { return [] }
        var result: [AnnotationSummary] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let annotations = page.annotations
                .filter(Self.isUserAnnotation)
                .sorted { $0.bounds.maxY > $1.bounds.maxY }
            for annotation in annotations {
                let tool = Self.tool(for: annotation)
                let text: String
                switch tool {
                case .text:
                    text = annotation.contents ?? ""
                case .pen:
                    text = "Zeichnung"
                default:
                    text = page.selection(for: annotation.bounds)?.string?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
                result.append(AnnotationSummary(
                    id: ObjectIdentifier(annotation),
                    pageNumber: index + 1,
                    tool: tool,
                    text: text.isEmpty ? tool.title : text,
                    color: Color(nsColor: (annotation.color.usingColorSpace(.sRGB) ?? annotation.color).withAlphaComponent(1))
                ))
            }
        }
        return result
    }

    func reveal(_ summary: AnnotationSummary) {
        guard let page = document?.page(at: summary.pageNumber - 1),
              let annotation = page.annotations.first(where: { ObjectIdentifier($0) == summary.id }) else { return }
        pdfView.go(to: annotation.bounds.insetBy(dx: -40, dy: -40), on: page)
        syncPage()
    }

    private static func isMarkup(_ annotation: PDFAnnotation) -> Bool {
        guard let type = annotation.type else { return false }
        return ["Highlight", "Underline", "StrikeOut"].contains(type)
    }

    /// Markierungen, die Nutzer:innen selbst setzen – Links und Formularfelder bleiben unberührt.
    private static func isUserAnnotation(_ annotation: PDFAnnotation) -> Bool {
        guard let type = annotation.type else { return false }
        return ["Highlight", "Underline", "StrikeOut", "Ink", "FreeText", "Text"].contains(type)
    }

    private static func tool(for annotation: PDFAnnotation) -> AnnotationTool {
        switch annotation.type ?? "" {
        case "Underline": .underline
        case "StrikeOut": .strikeOut
        case "Ink": .pen
        case "FreeText", "Text": .text
        default: .highlight
        }
    }

    // MARK: Speichern

    /// Speichert verzögert, damit mehrere Striche hintereinander nur einmal geschrieben werden.
    private func scheduleSave() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDelay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Schreibt ausstehende Änderungen sofort, z. B. beim Schließen des Readers.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges, let document else { return }
        guard let data = document.dataRepresentation() else {
            errorMessage = "Die Markierungen konnten nicht gespeichert werden."
            return
        }
        do {
            try save(data)
            hasUnsavedChanges = false
        } catch {
            errorMessage = "Die Markierungen konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}

