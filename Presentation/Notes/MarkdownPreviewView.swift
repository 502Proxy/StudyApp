import SwiftUI

/// Read-only rendering of Markdown using native SwiftUI text and the bundled KaTeX preview.
struct MarkdownPreviewView: View {
    let source: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(MarkdownBlockParser.parse(source)) { block in
                    MarkdownBlockView(block: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .textSelection(.enabled)
        }
        .background(Theme.editorBackground)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock
    @Environment(\.noteFontSize) private var fontSize

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if block.quoteDepth > 0 {
                Rectangle()
                    .fill(Theme.accent.opacity(0.6))
                    .frame(width: 3)
            }
            content
        }
        .padding(.leading, CGFloat(block.listDepth) * 18)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .paragraph:
            paragraph
        case .heading(let level):
            MarkdownInlineContentView(
                text: block.text,
                segments: block.inlineSegments,
                font: headingFont(level),
                color: Theme.textPrimary
            )
            .padding(.top, level <= 2 ? 6 : 2)
        case .code:
            Text(block.text)
                .font(.system(size: fontSize * 0.93, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.surfaceBorder)
                }
        case .horizontalRule:
            Rectangle()
                .fill(Theme.surfaceBorder)
                .frame(height: 1)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        case .table:
            if let table = block.table {
                MarkdownTableView(table: table)
            }
        }
    }

    private var paragraph: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let marker = block.listMarker {
                Text(marker)
                    .font(.system(size: fontSize).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            MarkdownInlineContentView(
                text: block.text,
                segments: block.inlineSegments,
                font: .system(size: fontSize),
                color: block.quoteDepth > 0 ? Theme.textSecondary : Theme.textPrimary
            )
        }
    }

    /// Überschriften wachsen proportional zur eingestellten Notizschrift.
    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .system(size: fontSize * 1.7, weight: .bold)
        case 2: .system(size: fontSize * 1.43, weight: .semibold)
        case 3: .system(size: fontSize * 1.21, weight: .semibold)
        default: .system(size: fontSize * 1.07, weight: .semibold)
        }
    }
}

/// Displays inline equations inside a word-wrapping flow. Display equations occupy their own row.
private struct MarkdownInlineContentView: View {
    let text: AttributedString
    let segments: [MarkdownInlineSegment]
    let font: Font
    let color: Color
    @Environment(\.noteFontSize) private var fontSize

    /// Formelflächen wachsen mit der Notizschrift.
    private var scale: CGFloat { CGFloat(fontSize / NoteFontSize.standard) }

    var body: some View {
        if segments.isEmpty {
            Text(text).font(font).foregroundStyle(color)
        } else if containsDisplayMath {
            displayMathContent
        } else {
            inlineMathContent
        }
    }

    private var containsDisplayMath: Bool {
        segments.contains { segment in
            if case .math(_, let displayMode) = segment.kind { return displayMode }
            return false
        }
    }

    private var inlineMathContent: some View {
        MarkdownFlowLayout(horizontalSpacing: 0, verticalSpacing: 1) {
            ForEach(Array(segments.enumerated()), id: \.offset) { entry in
                let segment = entry.element
                switch segment.kind {
                case .text(let attributed):
                    ForEach(Array(Self.wordFragments(in: attributed).enumerated()), id: \.offset) { entry in
                        Text(entry.element)
                            .font(font)
                            .foregroundStyle(color)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                case .math(let source, _):
                    LaTeXPreviewView(source: source, isInline: true)
                        .frame(width: Self.inlineFormulaWidth(source) * scale, height: 30 * scale)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayMathContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(segments.enumerated()), id: \.offset) { entry in
                let segment = entry.element
                switch segment.kind {
                case .text(let attributed):
                    Text(attributed)
                        .font(font)
                        .foregroundStyle(color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .math(let source, let displayMode):
                    LaTeXPreviewView(source: source, isInline: !displayMode)
                        .frame(maxWidth: .infinity)
                        .frame(height: (displayMode ? 76 : 34) * scale)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Split text on whitespace while preserving every AttributedString run.
    private static func wordFragments(in text: AttributedString) -> [AttributedString] {
        guard !text.characters.isEmpty else { return [] }
        var fragments: [AttributedString] = []
        var fragmentStart = text.startIndex

        for index in text.characters.indices {
            guard text.characters[index].isWhitespace else { continue }
            if fragmentStart < index {
                fragments.append(AttributedString(text[fragmentStart..<index]))
            }
            let next = text.characters.index(after: index)
            fragments.append(AttributedString(text[index..<next]))
            fragmentStart = next
        }
        if fragmentStart < text.endIndex {
            fragments.append(AttributedString(text[fragmentStart..<text.endIndex]))
        }
        return fragments
    }

    private static func inlineFormulaWidth(_ source: String) -> CGFloat {
        // A conservative estimate keeps short formulas inline without letting long ones
        // push the whole paragraph outside the note pane.
        CGFloat(min(240, max(48, source.count * 6)))
    }
}

/// A compact flow layout allows text fragments and formula views to wrap around one another.
private struct MarkdownFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 0
    var verticalSpacing: CGFloat = 1

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let availableWidth = max(1, proposal.width ?? 500)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > availableWidth {
                y += lineHeight + verticalSpacing
                x = 0
                lineHeight = 0
            }
            usedWidth = max(usedWidth, min(availableWidth, x + size.width))
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(availableWidth, max(usedWidth, proposal.width == nil ? usedWidth : availableWidth)),
                      height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                y += lineHeight + verticalSpacing
                x = 0
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct MarkdownTableView: View {
    let table: MarkdownTable

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { entry in
                        tableCell(entry.element, isHeader: true)
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { entry in
                    let row = entry.element
                    GridRow {
                        ForEach(Array(table.headers.indices), id: \.self) { index in
                            if row.indices.contains(index) {
                                tableCell(row[index], isHeader: false)
                            } else {
                                tableCell(MarkdownTableCell(segments: [.init(kind: .text(AttributedString("")))]), isHeader: false)
                            }
                        }
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.surfaceBorder)
            }
        }
        .scrollIndicators(.visible)
    }

    private func tableCell(_ cell: MarkdownTableCell, isHeader: Bool) -> some View {
        MarkdownTableCellView(cell: cell, isHeader: isHeader)
    }
}

private struct MarkdownTableCellView: View {
    let cell: MarkdownTableCell
    let isHeader: Bool
    @Environment(\.noteFontSize) private var fontSize

    var body: some View {
        Group {
            if cell.segments.count == 1, case .text(let text) = cell.segments[0].kind {
                Text(text)
                    .font(.system(size: fontSize, weight: isHeader ? .semibold : .regular))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                // Formula-bearing cells use the same renderer as paragraphs.
                MarkdownInlineContentView(
                    text: AttributedString(""),
                    segments: cell.segments,
                    font: .system(size: fontSize, weight: isHeader ? .semibold : .regular),
                    color: Theme.textPrimary
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minWidth: 90, maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(isHeader ? Theme.accent.opacity(0.10) : Theme.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.surfaceBorder).frame(width: 0.5) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.surfaceBorder).frame(height: 0.5) }
    }
}
