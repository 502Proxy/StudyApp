import Foundation
import Testing
@testable import StudyApp

@MainActor
struct MarkdownHTMLRendererTests {
    @Test func escapesUserTextSoItIsNeverParsedAsHTML() {
        let html = MarkdownHTMLRenderer.html(for: "<script>alert(1)</script> & \"x\"", format: .plainText)
        #expect(html.contains("&lt;script&gt;"))
        #expect(!html.contains("<script>"))
        #expect(html.contains("&amp;"))
    }

    @Test func rendersHeadingsEmphasisListsAndCode() {
        let html = MarkdownHTMLRenderer.html(for: "# Titel\n\n**fett** und *kursiv*\n\n1. Erstens\n2. Zweitens\n\n```\nlet x = 1\n```", format: .markdown)
        #expect(html.contains("<h2>Titel</h2>"))
        #expect(html.contains("<strong>fett</strong>"))
        #expect(html.contains("<em>kursiv</em>"))
        #expect(html.contains("<span class=\"marker\">1.</span>"))
        #expect(html.contains("<pre><code>let x = 1</code></pre>"))
    }

    @Test func keepsMathDelimitersForKaTeX() {
        let html = MarkdownHTMLRenderer.html(for: "Euler: $e^{i\\pi} + 1 = 0$", format: .markdown)
        #expect(html.contains("$e^{i\\pi} + 1 = 0$"))
    }

    @Test func documentContainsTitleSubtitleAndSections() {
        let document = PrintableDocument(
            title: "Analysis <I>",
            subtitle: "Stand heute",
            sections: [.init(heading: "Seite 1", content: "Inhalt", format: .plainText)]
        )
        let html = MarkdownHTMLRenderer.html(for: document)
        #expect(html.contains("Analysis &lt;I&gt;"))
        #expect(html.contains("<h2 class=\"section-title\">Seite 1</h2>"))
        #expect(PrintTemplate.page(for: document).contains("KaTeX/katex.min.js"))
    }
}
