import Foundation

/// Ein importiertes Foliensatz-PDF, das zu genau einem Modul gehört.
/// `fileName` ist der interne Dateiname im App-Speicher, nicht der Originalname.
struct SlideDocument: Identifiable, Hashable, Sendable {
    let id: UUID
    let moduleID: UUID
    var title: String
    let fileName: String
    let pageCount: Int
    let importedAt: Date
    /// Herkunft aus Stud.IP (Datei-ID und `chdate`), damit der Abgleich nichts doppelt lädt.
    var remoteID: String? = nil
    var remoteVersion: String? = nil
}
