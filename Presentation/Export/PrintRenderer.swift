import AppKit
import WebKit

enum PrintRendererError: LocalizedError {
    case missingResources
    case renderingFailed
    case noWindow

    var errorDescription: String? {
        switch self {
        case .missingResources: "Die Druckvorlage fehlt im App-Bundle."
        case .renderingFailed: "Das PDF konnte nicht erstellt werden."
        case .noWindow: "Zum Drucken muss ein StudyApp-Fenster geöffnet sein."
        }
    }
}

/// Setzt ein `PrintableDocument` mit WebKit als A4-Dokument: als PDF-Datei oder über den Druckdialog.
///
/// Das HTML liegt zusammen mit einer Kopie der KaTeX-Dateien in einem temporären Ordner,
/// damit Formeln auch offline gesetzt werden und die Sandbox den Zugriff erlaubt.
@MainActor
final class PrintRenderer: NSObject, WKNavigationDelegate {
    static let shared = PrintRenderer()

    /// A4 in Punkt.
    private static let paperSize = NSSize(width: 595.28, height: 841.89)
    private static let margin: CGFloat = 46

    private var webView: WKWebView?
    private var hostWindow: NSWindow?
    private var loadContinuation: CheckedContinuation<Void, Error>?
    private var printContinuation: CheckedContinuation<Bool, Never>?

    /// PDF-Daten des Dokuments, z. B. für den Export.
    func pdfData(for document: PrintableDocument) async throws -> Data {
        let outputURL = try workspace().appending(path: "export-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary().setObject(outputURL, forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString)

        guard try await runPrintOperation(for: document, printInfo: info, showsPanels: false) else {
            throw PrintRendererError.renderingFailed
        }
        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else { throw PrintRendererError.renderingFailed }
        return data
    }

    /// Zeigt den macOS-Druckdialog (dort ist auch „Als PDF sichern“ möglich).
    func print(_ document: PrintableDocument) async throws {
        _ = try await runPrintOperation(for: document, printInfo: printInfo(), showsPanels: true)
    }

    // MARK: Ablauf

    private func runPrintOperation(for document: PrintableDocument, printInfo: NSPrintInfo, showsPanels: Bool) async throws -> Bool {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) else {
            throw PrintRendererError.noWindow
        }
        let webView = try await loadedWebView(for: document)
        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = showsPanels
        operation.showsProgressPanel = showsPanels
        operation.jobTitle = document.title
        // Ohne feste Größe liefert WebKit beim Drucken leere Seiten.
        operation.view?.frame = NSRect(origin: .zero, size: Self.paperSize)

        let success = await withCheckedContinuation { continuation in
            printContinuation = continuation
            operation.runModal(
                for: window,
                delegate: self,
                didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
                contextInfo: nil
            )
        }
        self.webView = nil
        hostWindow = nil
        return success
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        printContinuation?.resume(returning: success)
        printContinuation = nil
    }

    private func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = Self.paperSize
        info.topMargin = Self.margin
        info.bottomMargin = Self.margin
        info.leftMargin = Self.margin
        info.rightMargin = Self.margin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    // MARK: Laden

    private func loadedWebView(for document: PrintableDocument) async throws -> WKWebView {
        let folder = try workspace()
        let pageURL = folder.appending(path: "print-\(UUID().uuidString).html")
        try PrintTemplate.page(for: document).write(to: pageURL, atomically: true, encoding: .utf8)

        let frame = NSRect(origin: .zero, size: Self.paperSize)
        let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = self
        // WebKit druckt zuverlässiger, wenn die Ansicht in einem (unsichtbaren) Fenster hängt.
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        self.webView = webView
        hostWindow = window

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadFileURL(pageURL, allowingReadAccessTo: folder)
        }
        try? FileManager.default.removeItem(at: pageURL)
        await waitUntilMathIsTypeset(in: webView)
        return webView
    }

    /// Die Seite setzt `window.studyAppReady`, sobald KaTeX fertig ist (höchstens ca. 3 Sekunden warten).
    private func waitUntilMathIsTypeset(in webView: WKWebView) async {
        for _ in 0..<30 {
            if let ready = try? await webView.evaluateJavaScript("window.studyAppReady === true") as? Bool, ready {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    /// Temporärer Ordner mit einer Kopie der KaTeX-Dateien, einmal pro App-Start angelegt.
    private func workspace() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "StudyAppPrint", directoryHint: .isDirectory)
        let katexCopy = folder.appending(path: "KaTeX", directoryHint: .isDirectory)
        if !FileManager.default.fileExists(atPath: katexCopy.path) {
            guard let source = LaTeXResources.pageURL?.deletingLastPathComponent() else {
                throw PrintRendererError.missingResources
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: katexCopy)
        }
        return folder
    }
}

/// HTML-Gerüst mit Druck-Stylesheet.
enum PrintTemplate {
    static func page(for document: PrintableDocument) -> String {
        """
        <!DOCTYPE html>
        <html lang="de">
        <head>
        <meta charset="utf-8">
        <title>\(MarkdownHTMLRenderer.escape(document.title))</title>
        <link rel="stylesheet" href="KaTeX/katex.min.css">
        <style>\(css)</style>
        <script defer src="KaTeX/katex.min.js"></script>
        <script defer src="KaTeX/contrib/auto-render.min.js"></script>
        </head>
        <body>
        \(MarkdownHTMLRenderer.html(for: document))
        <script>\(script)</script>
        </body>
        </html>
        """
    }

    private static let css = """
    :root { color-scheme: light; --accent: #4F46E5; --text: #14151A; --muted: #6B7080; --line: #E6E8EF; --soft: #F1F3F8; }
    html, body { margin: 0; padding: 0; background: #FFFFFF; color: var(--text); }
    body { font: 11pt/1.55 -apple-system, "Helvetica Neue", sans-serif; -webkit-print-color-adjust: exact; }
    header { border-bottom: 2px solid var(--accent); padding-bottom: 10pt; margin-bottom: 16pt; }
    .doc-title { font-size: 21pt; line-height: 1.2; margin: 0 0 4pt; font-weight: 700; }
    .doc-subtitle { color: var(--muted); margin: 0; font-size: 9.5pt; }
    section { margin-bottom: 14pt; }
    .section-title { font-size: 13pt; color: var(--accent); border-bottom: 1px solid var(--line); padding-bottom: 3pt; margin: 18pt 0 8pt; page-break-after: avoid; }
    h2 { font-size: 15pt; margin: 16pt 0 6pt; page-break-after: avoid; }
    h3 { font-size: 13pt; margin: 14pt 0 5pt; page-break-after: avoid; }
    h4, h5, h6 { font-size: 11.5pt; margin: 12pt 0 4pt; page-break-after: avoid; }
    p { margin: 0 0 7pt; }
    .li { display: flex; gap: 6pt; margin: 0 0 3pt; }
    .li .marker { color: var(--muted); min-width: 1.1em; text-align: right; }
    blockquote { margin: 6pt 0; padding: 2pt 0 2pt 10pt; border-left: 3px solid var(--accent); color: #3F4250; }
    pre { background: var(--soft); border: 1px solid var(--line); border-radius: 6pt; padding: 8pt 10pt; white-space: pre-wrap; font-size: 9.5pt; page-break-inside: avoid; }
    code { font-family: "SF Mono", Menlo, monospace; font-size: 0.92em; background: var(--soft); border-radius: 3pt; padding: 0 2pt; }
    pre code { background: none; padding: 0; }
    hr { border: none; border-top: 1px solid var(--line); margin: 12pt 0; }
    table { border-collapse: collapse; margin: 8pt 0; width: 100%; page-break-inside: avoid; font-size: 10pt; }
    th, td { border: 1px solid var(--line); padding: 4pt 7pt; text-align: left; vertical-align: top; }
    th { background: #EEF0FF; }
    a { color: var(--accent); text-decoration: none; }
    .plain, .latex { white-space: pre-wrap; }
    .katex-display { margin: 8pt 0; page-break-inside: avoid; }
    """

    private static let script = """
    window.addEventListener("load", function () {
      try {
        if (typeof renderMathInElement === "function") {
          renderMathInElement(document.body, {
            delimiters: [
              { left: "$$", right: "$$", display: true },
              { left: "\\\\[", right: "\\\\]", display: true },
              { left: "\\\\begin{equation}", right: "\\\\end{equation}", display: true },
              { left: "\\\\begin{align}", right: "\\\\end{align}", display: true },
              { left: "\\\\(", right: "\\\\)", display: false },
              { left: "$", right: "$", display: false }
            ],
            throwOnError: false
          });
        }
      } finally {
        window.studyAppReady = true;
      }
    });
    """
}
