import AppKit
import SwiftUI
import WebKit

/// Locates the bundled, offline KaTeX preview page.
///
/// The `KaTeX` folder (`Presentation/Resources/KaTeX`) has to be added to the
/// app target as a *folder reference*, so its sub-folders (`contrib`, `fonts`) survive.
enum LaTeXResources {
    static let pageURL: URL? = Bundle.main.url(
        forResource: "latex-preview",
        withExtension: "html",
        subdirectory: "KaTeX"
    )
}

/// LaTeX preview. Shows the formulas via `LaTeXWebView`, or the raw text with a hint
/// when the KaTeX resources are missing from the app bundle.
struct LaTeXPreviewView: View {
    let source: String
    /// Uses zero-padding/compact layout when embedded into a Markdown paragraph.
    var isInline: Bool = false
    @Environment(\.noteFontSize) private var fontSize

    var body: some View {
        if let pageURL = LaTeXResources.pageURL {
            LaTeXWebView(source: source, pageURL: pageURL, isInline: isInline, fontSize: fontSize)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("KaTeX fehlt im App-Bundle. Der Ordner „KaTeX“ muss als Ordnerreferenz zum Target gehören.",
                      systemImage: "exclamationmark.triangle")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
                ScrollView {
                    Text(source)
                        .font(.system(size: fontSize * 0.93, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(18)
            .background(Theme.editorBackground)
        }
    }
}

/// Adapter between SwiftUI and `WKWebView`: renders LaTeX with the bundled KaTeX, fully offline.
///
/// The page is loaded once; later edits only call `window.renderNote(…)` in JavaScript,
/// so typing does not reload the web view or reset its scroll position.
struct LaTeXWebView: NSViewRepresentable {
    let source: String
    let pageURL: URL
    var isInline: Bool = false
    var fontSize: Double = NoteFontSize.standard

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = NSColor.textBackgroundColor
        context.coordinator.webView = webView
        // Read access is limited to the KaTeX folder.
        webView.loadFileURL(pageURL, allowingReadAccessTo: pageURL.deletingLastPathComponent())
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(source, isInline: isInline, fontSize: fontSize)
    }

    /// Queues the latest source until the page has loaded, then forwards it to JavaScript.
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var isPageLoaded = false
        private var pendingRender: (source: String, isInline: Bool, fontSize: Double)?
        /// Zuletzt gerenderter Stand; unverändertes erneutes Rendern wird übersprungen.
        private var lastRender: (source: String, isInline: Bool, fontSize: Double)?

        func render(_ source: String, isInline: Bool = false, fontSize: Double = NoteFontSize.standard) {
            guard isPageLoaded else {
                pendingRender = (source, isInline, fontSize)
                return
            }
            if let lastRender, lastRender.source == source, lastRender.isInline == isInline, lastRender.fontSize == fontSize {
                return
            }
            guard let literal = Self.javaScriptLiteral(for: source) else { return }
            let inlineLiteral = isInline ? "true" : "false"
            lastRender = (source, isInline, fontSize)
            webView?.evaluateJavaScript("window.renderNote(\(literal), \(inlineLiteral), \(fontSize));", completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            if let pendingRender {
                self.pendingRender = nil
                render(pendingRender.source, isInline: pendingRender.isInline, fontSize: pendingRender.fontSize)
            }
        }

        /// The preview never navigates away: links inside notes are inert.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            navigationAction.navigationType == .linkActivated ? .cancel : .allow
        }

        /// A JSON string is also a valid JavaScript string literal, with all escaping done.
        private static func javaScriptLiteral(for text: String) -> String? {
            guard let data = try? JSONEncoder().encode(text) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }
}
