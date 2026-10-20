import AppKit
internal import PDFKit
import SwiftUI

/// Bettet die `PDFView` des Controllers in SwiftUI ein.
struct PDFKitView: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context: Context) -> PDFView {
        pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {}
}

/// Seitenleiste mit Vorschaubildern, gekoppelt an dieselbe `PDFView`.
struct PDFThumbnailStrip: NSViewRepresentable {
    let pdfView: PDFView

    func makeNSView(context: Context) -> PDFThumbnailView {
        let thumbnails = PDFThumbnailView()
        thumbnails.pdfView = pdfView
        thumbnails.thumbnailSize = CGSize(width: 110, height: 80)
        thumbnails.maximumNumberOfColumns = 1
        thumbnails.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: 0x1D1E24) : NSColor(hex: 0xF6F7FB)
        }
        return thumbnails
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {}
}
