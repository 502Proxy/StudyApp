import Foundation

/// Wandelt Notizen in druckbares HTML. Markdown läuft über denselben `MarkdownBlockParser` wie die
/// Vorschau, damit PDF und Bildschirm gleich aussehen. Formeln bleiben mit ihren Begrenzern im Text
/// und werden im Dokument von KaTeX gesetzt.
enum MarkdownHTMLRenderer {
    static func html(for document: PrintableDocument) -> String {
        var body = "<header><h1 class=\"doc-title\">\(escape(document.title))</h1>"
        if !document.subtitle.isEmpty {
            body += "<p class=\"doc-subtitle\">\(escape(document.subtitle))</p>"
        }
        body += "</header>\n"
        for section in document.sections {
            body += "<section>"
            if let heading = section.heading, !heading.isEmpty {
                body += "<h2 class=\"section-title\">\(escape(heading))</h2>"
            }
            body += html(for: section.content, format: section.format)
            body += "</section>\n"
        }
        return body
    }

    static func html(for content: String, format: NoteFormat) -> String {
        switch format {
        case .plainText:
            return "<div class=\"plain\">\(escape(content))</div>"
        case .latex:
            return "<div class=\"latex\">\(escape(content))</div>"
        case .markdown:
            return markdownHTML(content)
        }
    }

    // MARK: Markdown

    private static func markdownHTML(_ source: String) -> String {
        MarkdownBlockParser.parse(source).map(blockHTML).joined(separator: "\n")
    }

    private static func blockHTML(_ block: MarkdownBlock) -> String {
        let inner: String
        switch block.kind {
        case .heading(let level):
            let tag = "h\(min(max(level + 1, 2), 6))"
            inner = "<\(tag)>\(inlineHTML(block))</\(tag)>"
        case .code:
            inner = "<pre><code>\(escape(String(block.text.characters)))</code></pre>"
        case .horizontalRule:
            inner = "<hr>"
        case .table:
            inner = block.table.map(tableHTML) ?? ""
        case .paragraph:
            if let marker = block.listMarker {
                inner = "<div class=\"li\"><span class=\"marker\">\(escape(marker))</span><span>\(inlineHTML(block))</span></div>"
            } else if block.listDepth > 0 {
                // Weiterer Absatz eines Listenpunkts.
                inner = "<div class=\"li\"><span class=\"marker\"></span><span>\(inlineHTML(block))</span></div>"
            } else {
                inner = "<p>\(inlineHTML(block))</p>"
            }
        }
        var html = inner
        if block.listDepth > 0 {
            html = "<div style=\"margin-left: \(Double(block.listDepth) * 1.4)em\">\(html)</div>"
        }
        for _ in 0..<block.quoteDepth {
            html = "<blockquote>\(html)</blockquote>"
        }
        return html
    }

    private static func inlineHTML(_ block: MarkdownBlock) -> String {
        inlineHTML(text: block.text, segments: block.inlineSegments)
    }

    private static func inlineHTML(text: AttributedString, segments: [MarkdownInlineSegment]) -> String {
        guard !segments.isEmpty else { return attributedHTML(text) }
        return segments.map { segment in
            switch segment.kind {
            case .text(let attributed): attributedHTML(attributed)
            case .math(let source, _): escape(source)
            }
        }.joined()
    }

    /// Übersetzt die Inline-Formatierung (fett, kursiv, Code, durchgestrichen, Links) in HTML.
    private static func attributedHTML(_ text: AttributedString) -> String {
        var html = ""
        for run in text.runs {
            var piece = escape(String(text[run.range].characters))
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) { piece = "<code>\(piece)</code>" }
            if intent.contains(.stronglyEmphasized) { piece = "<strong>\(piece)</strong>" }
            if intent.contains(.emphasized) { piece = "<em>\(piece)</em>" }
            if intent.contains(.strikethrough) { piece = "<s>\(piece)</s>" }
            if let link = run.link, let scheme = link.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                piece = "<a href=\"\(escape(link.absoluteString))\">\(piece)</a>"
            }
            html += piece
        }
        return html.replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func tableHTML(_ table: MarkdownTable) -> String {
        func cell(_ cell: MarkdownTableCell, tag: String) -> String {
            let content = cell.segments.map { segment in
                switch segment.kind {
                case .text(let attributed): attributedHTML(attributed)
                case .math(let source, _): escape(source)
                }
            }.joined()
            return "<\(tag)>\(content)</\(tag)>"
        }
        var html = "<table><thead><tr>"
        html += table.headers.map { cell($0, tag: "th") }.joined()
        html += "</tr></thead><tbody>"
        for row in table.rows {
            html += "<tr>" + row.map { cell($0, tag: "td") }.joined() + "</tr>"
        }
        return html + "</tbody></table>"
    }

    // MARK: Hilfen

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }
}
