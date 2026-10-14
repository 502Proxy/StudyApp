import AppKit
import Observation
import PDFKit
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

/// Steuert eine `PDFView`: Seitenwechsel, Zoom und Markierungen.
/// Markierungen werden als echte PDF-Annotationen in die Kopie im App-Ordner geschrieben.
@MainActor
@Observable
final class PDFReaderController {
    let pdfView = PDFView()
    private(set) var pageIndex = 0
    private(set) var pageCount = 0
    private(set) var hasSelection = false
    private(set) var isLoaded = false
    var errorMessage: String?

    private let fileURL: URL
    private let document: PDFDocument?
    private let observers = ObserverBag()

    private static let highlightColor = NSColor.systemYellow.withAlphaComponent(0.45)

    init(fileURL: URL) {
        self.fileURL = fileURL
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
        pdfView.backgroundColor = NSColor.underPageBackgroundColor
        pdfView.document = document

        pageCount = document?.pageCount ?? 0
        isLoaded = document != nil

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

    // MARK: Markierungen

    func highlightSelection() {
        guard let selection = pdfView.currentSelection else { return }
        var changed = false

        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                guard !bounds.isEmpty else { continue }

                let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                annotation.color = Self.highlightColor
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
                changed = true
            }
        }

        pdfView.clearSelection()
        hasSelection = false
        if changed { persist() }
    }

    func removeHighlightsInSelection() {
        guard let selection = pdfView.currentSelection else { return }
        var changed = false

        for line in selection.selectionsByLine() {
            for page in line.pages {
                let bounds = line.bounds(for: page)
                for annotation in page.annotations where annotation.type?.contains("Highlight") == true {
                    let overlap = annotation.bounds.intersection(bounds)
                    // Nur Markierungen entfernen, die diese Zeile wirklich überdecken.
                    if !overlap.isNull, overlap.width > 1, overlap.height > bounds.height * 0.5 {
                        page.removeAnnotation(annotation)
                        changed = true
                    }
                }
            }
        }

        pdfView.clearSelection()
        hasSelection = false
        if changed { persist() }
    }

    /// Schreibt das PDF über eine temporäre Datei zurück, damit die Datei nie halb geschrieben bleibt.
    private func persist() {
        guard let document else { return }
        let temporaryURL = fileURL
            .deletingLastPathComponent()
            .appending(path: "\(UUID().uuidString).tmp", directoryHint: .notDirectory)

        guard document.write(to: temporaryURL) else {
            errorMessage = "Die Markierung konnte nicht gespeichert werden."
            return
        }
        do {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            errorMessage = "Die Markierung konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}
