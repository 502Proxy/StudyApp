import AppKit
internal import PDFKit

/// `PDFView`, die je nach Werkzeug Mausereignisse selbst verarbeitet: Zeichnen, Textfelder
/// platzieren und Radieren. Im Textmodus bleibt das normale Verhalten (Auswählen, Links) erhalten.
final class AnnotatingPDFView: PDFView {
    enum Interaction {
        case textSelection
        case draw
        case placeText
        case erase
    }

    var interaction: Interaction = .textSelection {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    /// Maustaste im Textmodus losgelassen – Zeitpunkt, um eine Auswahl zu markieren.
    var onSelectionFinished: (() -> Void)?
    var onStrokeBegan: ((PDFPage, CGPoint) -> Void)?
    var onStrokeMoved: ((CGPoint) -> Void)?
    var onStrokeEnded: (() -> Void)?
    /// Klick im Textfeld- oder Radiermodus, mit Seite und Punkt in Seitenkoordinaten.
    var onPageClick: ((PDFPage, CGPoint) -> Void)?

    private var strokePage: PDFPage?

    override func mouseDown(with event: NSEvent) {
        guard interaction != .textSelection, let (page, point) = pageLocation(of: event) else {
            super.mouseDown(with: event)
            return
        }
        switch interaction {
        case .draw:
            strokePage = page
            onStrokeBegan?(page, point)
        case .placeText, .erase:
            onPageClick?(page, point)
        case .textSelection:
            break
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard interaction == .draw, let page = strokePage else {
            if interaction == .textSelection { super.mouseDragged(with: event) }
            return
        }
        let viewPoint = convert(event.locationInWindow, from: nil)
        onStrokeMoved?(convert(viewPoint, to: page))
    }

    override func mouseUp(with event: NSEvent) {
        switch interaction {
        case .textSelection:
            super.mouseUp(with: event)
            onSelectionFinished?()
        case .draw:
            if strokePage != nil { onStrokeEnded?() }
            strokePage = nil
        case .placeText, .erase:
            break
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        switch interaction {
        case .textSelection: break
        case .draw: addCursorRect(bounds, cursor: .crosshair)
        case .placeText: addCursorRect(bounds, cursor: .iBeam)
        case .erase: addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    private func pageLocation(of event: NSEvent) -> (PDFPage, CGPoint)? {
        let viewPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: viewPoint, nearest: true) else { return nil }
        return (page, convert(viewPoint, to: page))
    }
}
