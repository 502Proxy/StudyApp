import Foundation
import Testing
@testable import StudyApp

@MainActor
struct MarkdownBlockParserTests {
    private func plain(_ block: MarkdownBlock) -> String {
        String(block.text.characters)
    }

    @Test func blankSourceYieldsNoBlocks() {
        #expect(MarkdownBlockParser.parse("").isEmpty)
        #expect(MarkdownBlockParser.parse("  \n\n ").isEmpty)
    }

    @Test func headingAndParagraphBecomeSeparateBlocks() {
        let blocks = MarkdownBlockParser.parse("# Titel\n\nText darunter")

        #expect(blocks.map(\.kind) == [.heading(level: 1), .paragraph])
        #expect(blocks.map(plain) == ["Titel", "Text darunter"])
    }

    @Test func unorderedListGetsBulletMarkers() {
        let blocks = MarkdownBlockParser.parse("- eins\n- zwei")

        #expect(blocks.map(plain) == ["eins", "zwei"])
        #expect(blocks.map(\.listMarker) == ["•", "•"])
    }

    @Test func orderedListGetsNumberedMarkers() {
        let blocks = MarkdownBlockParser.parse("1. erst\n2. dann")

        #expect(blocks.map(\.listMarker) == ["1.", "2."])
    }

    @Test func nestedListItemsAreIndented() {
        let blocks = MarkdownBlockParser.parse("- oben\n  - unten")

        #expect(blocks.map(\.listDepth) == [0, 1])
    }

    @Test func fencedCodeKeepsLanguageAndDropsTrailingNewline() {
        let blocks = MarkdownBlockParser.parse("```swift\nlet x = 1\n```")

        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == .code(language: "swift"))
        #expect(blocks.first.map(plain) == "let x = 1")
    }

    @Test func blockQuoteIsMarkedAsQuoted() {
        let blocks = MarkdownBlockParser.parse("> Zitat")

        #expect(blocks.first?.quoteDepth == 1)
        #expect(blocks.first.map(plain) == "Zitat")
    }
    @Test func markdownTableCreatesHeadersAndRows() {
        let blocks = MarkdownBlockParser.parse("""
        | Begriff | Bedeutung |
        | --- | :---: |
        | API | Schnittstelle |
        | UI | Oberfläche |
        """)

        #expect(blocks.count == 1)
        #expect(blocks.first?.kind == .table)
        #expect(blocks.first?.table?.headers.count == 2)
        #expect(blocks.first?.table?.rows.count == 2)
    }

    @Test func horizontalRuleIsRenderedAsItsOwnBlock() {
        let blocks = MarkdownBlockParser.parse("Vorher\n\n---\n\nNachher")

        #expect(blocks.map(\.kind) == [.paragraph, .horizontalRule, .paragraph])
    }

    @Test func inlineAndDisplayMathAreSeparatedFromMarkdownText() {
        let blocks = MarkdownBlockParser.parse("Text mit $x^2$ danach.\n\n$$\n\\frac{1}{2}\n$$")
        let segments = blocks.flatMap(\.inlineSegments)
        let formulas = segments.compactMap { segment -> (String, Bool)? in
            if case .math(let source, let display) = segment.kind { return (source, display) }
            return nil
        }

        #expect(formulas.count == 2)
        #expect(formulas.contains(where: { $0.0 == "$x^2$" && !$0.1 }))
        #expect(formulas.contains(where: { $0.0.contains("\\frac{1}{2}") && $0.1 }))
    }

    @Test func mathInsideInlineCodeIsNotRenderedAsFormula() {
        let blocks = MarkdownBlockParser.parse("Code: `$x$`, Mathematik: $y$")
        let formulas = blocks.flatMap(\.inlineSegments).compactMap { segment -> String? in
            if case .math(let source, _) = segment.kind { return source }
            return nil
        }

        #expect(formulas == ["$y$"])
    }

}
