import Foundation
internal import PDFKit

struct PDFKitInspector: PDFInspector {
    func pageCount(at url: URL) -> Int? {
        guard let document = PDFDocument(url: url) else { return nil }
        // Gesperrte (passwortgeschützte) PDFs liefern 0 Seiten und gelten hier als unlesbar.
        return document.pageCount > 0 ? document.pageCount : nil
    }
}
