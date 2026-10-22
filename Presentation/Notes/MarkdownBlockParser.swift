import Foundation

/// One renderable inline fragment. Math keeps its original delimiters so the bundled
/// KaTeX auto-renderer can choose inline/display layout consistently.
struct MarkdownInlineSegment: Equatable {
    enum Kind: Equatable {
        case text(AttributedString)
        case math(source: String, displayMode: Bool)
    }

    let kind: Kind
}

struct MarkdownTableCell: Equatable {
    let segments: [MarkdownInlineSegment]
}

struct MarkdownTable: Equatable {
    let headers: [MarkdownTableCell]
    let rows: [[MarkdownTableCell]]
}

/// One block-level element of a Markdown document, ready to be drawn by `MarkdownPreviewView`.
struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading(level: Int)
        case code(language: String?)
        case horizontalRule
        case table
    }

    /// Position in the document; stable while the user edits text below this block.
    let id: Int
    let kind: Kind
    /// Inline-formatted text (bold, italic, code, links, strikethrough).
    let text: AttributedString
    /// Number of enclosing block quotes.
    let quoteDepth: Int
    /// `"•"` or `"1."` for the first paragraph of a list item, otherwise `nil`.
    let listMarker: String?
    /// Nesting level of the enclosing list items (0 = not in a list or top level).
    let listDepth: Int
    /// Set for table blocks; the textual fields above are otherwise unchanged.
    let table: MarkdownTable?
    /// Non-empty only if the block contains `$…$`, `\(…\)` or display math.
    let inlineSegments: [MarkdownInlineSegment]

    init(
        id: Int,
        kind: Kind,
        text: AttributedString,
        quoteDepth: Int,
        listMarker: String?,
        listDepth: Int,
        table: MarkdownTable? = nil,
        inlineSegments: [MarkdownInlineSegment] = []
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.quoteDepth = quoteDepth
        self.listMarker = listMarker
        self.listDepth = listDepth
        self.table = table
        self.inlineSegments = inlineSegments
    }
}

/// Parses Markdown into flat blocks while retaining Foundation's inline formatting.
/// Tables and horizontal rules are handled explicitly because `AttributedString` does
/// not expose their block structure in a way the SwiftUI renderer can use directly.
enum MarkdownBlockParser {
    static func parse(_ source: String) -> [MarkdownBlock] {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let tokenized = tokenizeMath(in: source)
        let lines = tokenized.source.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var markdownLines: [String] = []
        var fence: FenceMarker?
        var lineIndex = 0

        func flushMarkdown() {
            guard !markdownLines.isEmpty else { return }
            let markdown = markdownLines.joined(separator: "\n")
            markdownLines.removeAll(keepingCapacity: true)
            let parsed = parseMarkdownSegment(markdown)
            blocks.append(contentsOf: parsed.map { attachingMathSegments(to: $0, expressions: tokenized.expressions) })
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]

            if let openFence = fence {
                markdownLines.append(line)
                if closesFence(line, marker: openFence) { fence = nil }
                lineIndex += 1
                continue
            }

            if let opened = openingFence(in: line) {
                markdownLines.append(line)
                fence = opened
                lineIndex += 1
                continue
            }

            if lineIndex + 1 < lines.count,
               isTableHeader(line),
               isTableDelimiter(lines[lineIndex + 1]) {
                flushMarkdown()
                let headerCells = splitTableRow(line).map {
                    parseTableCell($0, expressions: tokenized.expressions)
                }
                let columnCount = headerCells.count
                var tableRows: [[MarkdownTableCell]] = []
                lineIndex += 2 // header and delimiter

                while lineIndex < lines.count {
                    let candidate = lines[lineIndex]
                    guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          containsUnescapedPipe(candidate) else { break }
                    var cells = splitTableRow(candidate).map {
                        parseTableCell($0, expressions: tokenized.expressions)
                    }
                    if cells.count < columnCount {
                        cells.append(contentsOf: repeatElement(
                            MarkdownTableCell(segments: [.init(kind: .text(AttributedString("")))]),
                            count: columnCount - cells.count
                        ))
                    } else if cells.count > columnCount {
                        cells = Array(cells.prefix(columnCount - 1)) + [
                            MarkdownTableCell(segments: mergeExtraCells(cells, from: columnCount - 1))
                        ]
                    }
                    tableRows.append(cells)
                    lineIndex += 1
                }

                blocks.append(MarkdownBlock(
                    id: blocks.count,
                    kind: .table,
                    text: AttributedString(""),
                    quoteDepth: 0,
                    listMarker: nil,
                    listDepth: 0,
                    table: MarkdownTable(headers: headerCells, rows: tableRows)
                ))
                continue
            }

            if isHorizontalRule(line) {
                flushMarkdown()
                blocks.append(MarkdownBlock(
                    id: blocks.count,
                    kind: .horizontalRule,
                    text: AttributedString(""),
                    quoteDepth: 0,
                    listMarker: nil,
                    listDepth: 0
                ))
                lineIndex += 1
                continue
            }

            markdownLines.append(line)
            lineIndex += 1
        }
        flushMarkdown()

        // Segment parsers start IDs at zero; make IDs unique across Markdown, table and rule blocks.
        return blocks.enumerated().map { index, block in
            MarkdownBlock(
                id: index,
                kind: block.kind,
                text: block.text,
                quoteDepth: block.quoteDepth,
                listMarker: block.listMarker,
                listDepth: block.listDepth,
                table: block.table,
                inlineSegments: block.inlineSegments
            )
        }
    }

    // MARK: Standard Markdown blocks

    private static func parseMarkdownSegment(_ source: String) -> [MarkdownBlock] {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let attributed = try? AttributedString(markdown: source, options: options) else {
            return [MarkdownBlock(
                id: 0, kind: .paragraph, text: AttributedString(source),
                quoteDepth: 0, listMarker: nil, listDepth: 0
            )]
        }

        var builder = BlockBuilder()
        for run in attributed.runs {
            builder.append(
                text: AttributedString(attributed[run.range]),
                components: run.presentationIntent?.components ?? []
            )
        }
        return builder.finish()
    }

    private static func attachingMathSegments(
        to block: MarkdownBlock,
        expressions: [String: MathExpression]
    ) -> MarkdownBlock {
        guard case .code = block.kind else {
            let segments = inlineSegments(in: block.text, expressions: expressions)
            guard !segments.isEmpty else { return block }
            return MarkdownBlock(
                id: block.id,
                kind: block.kind,
                text: block.text,
                quoteDepth: block.quoteDepth,
                listMarker: block.listMarker,
                listDepth: block.listDepth,
                table: block.table,
                inlineSegments: segments
            )
        }
        return block
    }

    private static func inlineSegments(
        in attributed: AttributedString,
        expressions: [String: MathExpression]
    ) -> [MarkdownInlineSegment] {
        guard !expressions.isEmpty else { return [] }
        let raw = String(attributed.characters)
        guard expressions.keys.contains(where: { raw.contains($0) }) else { return [] }

        var result: [MarkdownInlineSegment] = []
        var stringCursor = raw.startIndex
        var attributedCursor = attributed.startIndex

        while stringCursor < raw.endIndex {
            var nearest: (token: String, range: Range<String.Index>, expression: MathExpression)?
            for (token, expression) in expressions {
                guard let range = raw.range(of: token, range: stringCursor..<raw.endIndex) else { continue }
                if nearest == nil || range.lowerBound < nearest!.range.lowerBound {
                    nearest = (token, range, expression)
                }
            }

            guard let match = nearest,
                  let mathStart = AttributedString.Index(match.range.lowerBound, within: attributed),
                  let mathEnd = AttributedString.Index(match.range.upperBound, within: attributed) else {
                break
            }

            if attributedCursor < mathStart {
                result.append(.init(kind: .text(AttributedString(attributed[attributedCursor..<mathStart]))))
            }
            result.append(.init(kind: .math(
                source: match.expression.source,
                displayMode: match.expression.displayMode
            )))
            attributedCursor = mathEnd
            stringCursor = match.range.upperBound
        }

        if attributedCursor < attributed.endIndex {
            result.append(.init(kind: .text(AttributedString(attributed[attributedCursor..<attributed.endIndex]))))
        }
        return result
    }

    // MARK: Tables and horizontal rules

    private static func isTableHeader(_ line: String) -> Bool {
        containsUnescapedPipe(line) && !splitTableRow(line).isEmpty
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let withoutAlignment = trimmed.replacingOccurrences(of: ":", with: "")
            return withoutAlignment.count >= 3 && withoutAlignment.allSatisfy { $0 == "-" }
        }
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, ["-", "*", "_"].contains(first) else {
            return false
        }
        return compact.allSatisfy { $0 == first }
    }

    private static func containsUnescapedPipe(_ line: String) -> Bool {
        splitTableRow(line).count > 1
    }

    private static func splitTableRow(_ source: String) -> [String] {
        var line = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("|") { line.removeFirst() }
        if line.hasSuffix("|") { line.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaped = false
        var backtickRun = 0
        var index = line.startIndex

        while index < line.endIndex {
            let character = line[index]
            if escaped {
                current.append(character)
                escaped = false
                index = line.index(after: index)
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                index = line.index(after: index)
                continue
            }
            if character == "`" {
                var end = index
                while end < line.endIndex, line[end] == "`" { end = line.index(after: end) }
                let runLength = line.distance(from: index, to: end)
                if backtickRun == 0 {
                    backtickRun = runLength
                } else if backtickRun == runLength {
                    backtickRun = 0
                }
                current += line[index..<end]
                index = end
                continue
            }
            if character == "|", backtickRun == 0 {
                cells.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        cells.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return cells
    }

    private static func parseTableCell(
        _ source: String,
        expressions: [String: MathExpression]
    ) -> MarkdownTableCell {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let attributed = (try? AttributedString(markdown: source, options: options)) ?? AttributedString(source)
        let segments = inlineSegments(in: attributed, expressions: expressions)
        if !segments.isEmpty { return MarkdownTableCell(segments: segments) }
        return MarkdownTableCell(segments: [.init(kind: .text(attributed))])
    }

    private static func mergeExtraCells(
        _ cells: [MarkdownTableCell],
        from start: Int
    ) -> [MarkdownInlineSegment] {
        var segments: [MarkdownInlineSegment] = []
        for index in start..<cells.count {
            if index > start {
                segments.append(.init(kind: .text(AttributedString(" | "))))
            }
            segments.append(contentsOf: cells[index].segments)
        }
        return segments
    }

    // MARK: Math tokenization

    private struct MathExpression: Equatable {
        let source: String
        let displayMode: Bool
    }

    private struct MathCandidate {
        let range: NSRange
        let displayMode: Bool
    }

    private struct FenceMarker {
        let character: Character
        let length: Int
    }

    private static func tokenizeMath(in source: String) -> (source: String, expressions: [String: MathExpression]) {
        let lines = source.components(separatedBy: "\n")
        var output = ""
        var regularText = ""
        var expressions: [String: MathExpression] = [:]
        var nextID = 0
        var fence: FenceMarker?

        func flushRegularText() {
            guard !regularText.isEmpty else { return }
            output += tokenizeMath(inRegularText: regularText, expressions: &expressions, nextID: &nextID)
            regularText = ""
        }

        for (index, line) in lines.enumerated() {
            let hasLineBreak = index < lines.count - 1
            if let openFence = fence {
                output += line
                if hasLineBreak { output += "\n" }
                if closesFence(line, marker: openFence) { fence = nil }
                continue
            }

            if let opened = openingFence(in: line) {
                flushRegularText()
                output += line
                if hasLineBreak { output += "\n" }
                fence = opened
                continue
            }

            regularText += line
            if hasLineBreak { regularText += "\n" }
        }
        flushRegularText()
        return (output, expressions)
    }

    private static func tokenizeMath(
        inRegularText source: String,
        expressions: inout [String: MathExpression],
        nextID: inout Int
    ) -> String {
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)
        let inlineCodeRanges = rangesOfInlineCode(in: source)
        let patterns: [(String, Bool)] = [
            (#"(?s)\$\$(.+?)\$\$"#, true),
            (#"(?s)\\\[(.+?)\\\]"#, true),
            (#"(?s)\\begin\{(equation\*?|align\*?|gather\*?)\}(.+?)\\end\{\1\}"#, true),
            (#"\\\((.+?)\\\)"#, false),
            (#"(?<!\\)\$(?!\$)(\S(?:[^$\n]*?\S)?)\$(?!\$)"#, false)
        ]

        var candidates: [MathCandidate] = []
        for (pattern, displayMode) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            for match in regex.matches(in: source, range: fullRange) where match.range.length > 0 {
                candidates.append(MathCandidate(range: match.range, displayMode: displayMode))
            }
        }
        candidates.sort {
            if $0.range.location == $1.range.location { return $0.range.length > $1.range.length }
            return $0.range.location < $1.range.location
        }

        var selected: [MathCandidate] = []
        for candidate in candidates {
            guard !inlineCodeRanges.contains(where: { rangesOverlap($0, candidate.range) }),
                  !selected.contains(where: { rangesOverlap($0.range, candidate.range) }) else { continue }
            selected.append(candidate)
        }

        var replaced = source
        for candidate in selected.reversed() {
            let expression = nsSource.substring(with: candidate.range)
            let token = "STUDYAPPMATHTOKEN\(nextID)END"
            nextID += 1
            expressions[token] = MathExpression(source: expression, displayMode: candidate.displayMode)
            replaced = (replaced as NSString).replacingCharacters(in: candidate.range, with: token)
        }
        return replaced
    }

    private static func rangesOfInlineCode(in source: String) -> [NSRange] {
        let nsSource = source as NSString
        var ranges: [NSRange] = []
        var index = 0

        while index < nsSource.length {
            guard nsSource.character(at: index) == 96 else {
                index += 1
                continue
            }
            let start = index
            while index < nsSource.length, nsSource.character(at: index) == 96 { index += 1 }
            let runLength = index - start
            var search = index
            var matchingRange: NSRange?

            while search < nsSource.length {
                guard nsSource.character(at: search) == 96 else {
                    search += 1
                    continue
                }
                let closingStart = search
                while search < nsSource.length, nsSource.character(at: search) == 96 { search += 1 }
                if search - closingStart == runLength {
                    matchingRange = NSRange(location: start, length: search - start)
                    break
                }
            }

            if let matchingRange {
                ranges.append(matchingRange)
                index = NSMaxRange(matchingRange)
            }
        }
        return ranges
    }

    private static func rangesOverlap(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
        lhs.location < NSMaxRange(rhs) && rhs.location < NSMaxRange(lhs)
    }

    private static func openingFence(in line: String) -> FenceMarker? {
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        guard leadingSpaces <= 3 else { return nil }
        let remainder = line.dropFirst(leadingSpaces)
        guard let first = remainder.first, first == "`" || first == "~" else { return nil }
        let length = remainder.prefix(while: { $0 == first }).count
        guard length >= 3 else { return nil }
        return FenceMarker(character: first, length: length)
    }

    private static func closesFence(_ line: String, marker: FenceMarker) -> Bool {
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        guard leadingSpaces <= 3 else { return false }
        let remainder = line.dropFirst(leadingSpaces)
        let length = remainder.prefix(while: { $0 == marker.character }).count
        guard length >= marker.length else { return false }
        return remainder.dropFirst(length).allSatisfy(\.isWhitespace)
    }
}

// MARK: - PresentationIntent grouping

private struct BlockBuilder {
    private var blocks: [MarkdownBlock] = []
    private var currentIdentity: Int?
    private var currentComponents: [PresentationIntent.IntentType] = []
    private var currentText = AttributedString()
    private var hasOpenBlock = false
    /// Identities of list items that already got their marker (a list item can hold several paragraphs).
    private var markedListItems: Set<Int> = []

    mutating func append(text: AttributedString, components: [PresentationIntent.IntentType]) {
        // The innermost component (paragraph, header, code block) identifies the block.
        let identity = components.first?.identity
        if hasOpenBlock, identity != currentIdentity {
            flush()
        }
        if !hasOpenBlock {
            hasOpenBlock = true
            currentIdentity = identity
            currentComponents = components
        }
        currentText.append(text)
    }

    mutating func finish() -> [MarkdownBlock] {
        flush()
        return blocks
    }

    private mutating func flush() {
        guard hasOpenBlock else { return }
        defer {
            hasOpenBlock = false
            currentIdentity = nil
            currentComponents = []
            currentText = AttributedString()
        }

        var kind = MarkdownBlock.Kind.paragraph
        var quoteDepth = 0
        var listItemCount = 0
        var marker: String?

        // Components are ordered from the innermost to the outermost.
        for (index, component) in currentComponents.enumerated() {
            switch component.kind {
            case .header(let level):
                kind = .heading(level: level)
            case .codeBlock(let language):
                kind = .code(language: language?.isEmpty == false ? language : nil)
            case .blockQuote:
                quoteDepth += 1
            case .listItem(let ordinal):
                listItemCount += 1
                // Only the innermost item decides the marker, and only its first paragraph shows it.
                if listItemCount == 1, markedListItems.insert(component.identity).inserted {
                    marker = Self.marker(ordinal: ordinal, parent: currentComponents[safe: index + 1])
                }
            default:
                break
            }
        }

        var text = currentText
        if case .code = kind {
            let trimmed = String(text.characters).trimmingCharacters(in: .newlines)
            text = AttributedString(trimmed)
        }

        blocks.append(MarkdownBlock(
            id: blocks.count, kind: kind, text: text,
            quoteDepth: quoteDepth, listMarker: marker, listDepth: max(listItemCount - 1, 0)
        ))
    }

    private static func marker(ordinal: Int, parent: PresentationIntent.IntentType?) -> String {
        if let parent, case .orderedList = parent.kind {
            return "\(ordinal)."
        }
        return "•"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
