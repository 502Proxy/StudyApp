import Foundation

/// Ablage der Dateien im App-Ordner. Die Domain kennt nur Dateinamen,
/// den konkreten Speicherort bestimmt die Data-Schicht.
protocol FileStorage: Sendable {
    /// Kopiert die Datei unter dem angegebenen Namen in den App-Speicher.
    func store(copyOf sourceURL: URL, as fileName: String) throws
    func url(for fileName: String) -> URL
    /// Ersetzt den Inhalt einer Datei atomar, z. B. ein PDF nach dem Markieren.
    func write(_ data: Data, as fileName: String) throws
    /// Entfernt die Datei. Eine bereits fehlende Datei ist kein Fehler.
    func remove(fileName: String) throws
}

/// Prüft PDFs, ohne dass die Domain PDFKit kennen muss.
protocol PDFInspector: Sendable {
    /// Seitenzahl oder `nil`, wenn die Datei keine lesbare PDF ist.
    func pageCount(at url: URL) -> Int?
}
