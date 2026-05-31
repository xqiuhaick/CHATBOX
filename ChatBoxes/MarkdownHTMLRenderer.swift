import AppKit
import SwiftUI

// MARK: - Environment

struct MarkdownSearchResultsKey: EnvironmentKey {
    static let defaultValue: [WebSearchResultItem] = []
}

extension EnvironmentValues {
    var markdownSearchResults: [WebSearchResultItem] {
        get { self[MarkdownSearchResultsKey.self] }
        set { self[MarkdownSearchResultsKey.self] = newValue }
    }
}

private extension Color {
    static let markdownRendererTextPrimary = Color.primary
    static let markdownRendererLinkBlue = Color.accentColor
    static let markdownRendererBlockquoteBorder = Color.secondary.opacity(0.35)
    static let markdownRendererTableBorder = Color.primary.opacity(0.12)
    static let markdownRendererTableHeader = Color.primary.opacity(0.05)
    static let markdownRendererInlineCodeBackground = Color.primary.opacity(0.06)
}

// MARK: - Public API

struct MarkdownHTMLBlock: View {
    let text: String
    let baseFontSize: CGFloat
    let expandToWidth: Bool
    var searchResults: [WebSearchResultItem] = []

    var body: some View {
        MarkdownRichContentView(text: text, baseFontSize: baseFontSize)
            .frame(maxWidth: expandToWidth ? .infinity : nil, alignment: .leading)
            .environment(\.markdownSearchResults, searchResults)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    NSWorkspace.shared.open(url)
                    return .handled
                }
            )
    }
}

// MARK: - Rich Markdown Layout

private struct MarkdownRichContentView: View {
    let text: String
    let baseFontSize: CGFloat
    private let segments: [MarkdownSegment]

    init(text: String, baseFontSize: CGFloat) {
        self.text = text
        self.baseFontSize = baseFontSize
        self.segments = MarkdownSegmentParser.parse(text)
    }

    var body: some View {
        if segments.isEmpty {
            MarkdownMixedInlineView(source: text, baseFontSize: baseFontSize)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    segmentView(segment)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: MarkdownSegment) -> some View {
        switch segment {
        case .heading(let level, let content):
            Text(content)
                .font(.system(size: headingSize(for: level), weight: .semibold))
                .foregroundStyle(Color.markdownRendererTextPrimary)
                .padding(.top, level <= 2 ? 4 : 0)

        case .paragraph(let content):
            paragraphView(content)

        case .mathBlock(let latex):
            KaTeXBlockView(latex: latex, displayMode: true)

        case .list(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownListItemView(item: item, baseFontSize: baseFontSize)
                }
            }

        case .image(let alt, let url):
            MarkdownImageView(alt: alt, urlString: url)

        case .blockquote(let content):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.markdownRendererBlockquoteBorder)
                    .frame(width: 3)
                MarkdownMixedInlineView(source: content, baseFontSize: baseFontSize)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

        case .table(let headers, let rows):
            MarkdownTableView(headers: headers, rows: rows, baseFontSize: baseFontSize)

        case .thematicBreak:
            Divider()
                .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func paragraphView(_ content: String) -> some View {
        if let split = CanvasPreviewSupport.splitTextAndMarkup(content) {
            VStack(alignment: .leading, spacing: 10) {
                if !split.text.isEmpty {
                    MarkdownMixedInlineView(source: split.text, baseFontSize: baseFontSize)
                        .foregroundStyle(Color.markdownRendererTextPrimary)
                }
                CanvasCodeBlockView(language: split.language, code: split.markup)
            }
        } else if let image = MarkdownImageParser.standaloneLine(content) {
            MarkdownImageView(alt: image.alt, urlString: image.url)
        } else if MarkdownHTMLDetector.isLikelyHTMLBlock(content)
            || CanvasPreviewSupport.looksLikeSVG(content)
            || CanvasPreviewSupport.looksLikeHTML(content) {
            CanvasCodeBlockView(
                language: CanvasPreviewSupport.inferLanguage(for: content),
                code: content
            )
        } else {
            MarkdownMixedInlineView(source: content, baseFontSize: baseFontSize)
                .foregroundStyle(Color.markdownRendererTextPrimary)
        }
    }

    private func headingSize(for level: Int) -> CGFloat {
        switch level {
        case 1: return baseFontSize + 9
        case 2: return baseFontSize + 6
        case 3: return baseFontSize + 3
        case 4: return baseFontSize + 1
        default: return baseFontSize
        }
    }
}

// MARK: - Table

private struct MarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    let baseFontSize: CGFloat

    private var columns: [String] {
        if headers.isEmpty, let first = rows.first {
            return first
        }
        return headers
    }

    var body: some View {
        let columnCount = max(columns.count, rows.map(\.count).max() ?? 0)
        if columnCount == 0 {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    if !columns.isEmpty {
                        tableRow(columns, isHeader: true)
                        Divider()
                    }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        tableRow(paddedRow(row, count: columnCount), isHeader: false)
                        Divider()
                    }
                }
                .frame(minWidth: max(CGFloat(columnCount) * 120, 280), alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.markdownRendererTableBorder, lineWidth: 0.5)
            }
        }
    }

    private func tableRow(_ cells: [String], isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                MarkdownTableCell(text: cell, baseFontSize: baseFontSize, isHeader: isHeader)
                if index < cells.count - 1 {
                    Divider()
                }
            }
        }
        .background(isHeader ? Color.markdownRendererTableHeader : Color.clear)
    }

    private func paddedRow(_ row: [String], count: Int) -> [String] {
        var result = row
        while result.count < count {
            result.append("")
        }
        return Array(result.prefix(count))
    }
}

private struct MarkdownTableCell: View {
    let text: String
    let baseFontSize: CGFloat
    let isHeader: Bool

    var body: some View {
        Group {
            MarkdownMixedInlineView(source: text, baseFontSize: baseFontSize)
                .fontWeight(isHeader ? .semibold : .regular)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .tint(Color.markdownRendererLinkBlue)
    }
}

// MARK: - List Tree

enum MarkdownListMarker: Equatable {
    case bullet
    case ordered(Int)
    case task(checked: Bool)
}

struct MarkdownListItem: Equatable {
    var marker: MarkdownListMarker
    var text: String
    var children: [MarkdownListItem]
}

private struct MarkdownListItemView: View {
    let item: MarkdownListItem
    let baseFontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                markerView
                MarkdownMixedInlineView(source: item.text, baseFontSize: baseFontSize)
            }
            if !item.children.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                        MarkdownListItemView(item: child, baseFontSize: baseFontSize)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    @ViewBuilder
    private var markerView: some View {
        switch item.marker {
        case .bullet:
            Text("•")
                .font(.system(size: baseFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
        case .ordered(let number):
            Text("\(number).")
                .font(.system(size: baseFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .trailing)
        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: baseFontSize))
                .foregroundStyle(checked ? Color.accentColor : .secondary)
        }
    }
}

// MARK: - Parser

private enum MarkdownSegment {
    case heading(level: Int, text: String)
    case paragraph(String)
    case mathBlock(String)
    case list([MarkdownListItem])
    case image(alt: String, url: String)
    case blockquote(String)
    case table(headers: [String], rows: [[String]])
    case thematicBreak
}

enum MarkdownHTMLDetector {
    static func isLikelyHTMLBlock(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">") else { return false }
        return trimmed.range(of: #"</?[a-zA-Z][^>]*>"#, options: .regularExpression) != nil
    }
}

struct MarkdownRichInlineText: View {
    let text: String
    let baseFontSize: CGFloat

    var body: some View {
        if let attributed = MarkdownInlineRenderer.attributedString(from: text, baseFontSize: baseFontSize) {
            Text(attributed)
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .tint(Color.markdownRendererLinkBlue)
        } else {
            Text(text)
                .font(.system(size: baseFontSize))
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum MarkdownSegmentParser {
    static func parse(_ text: String) -> [MarkdownSegment] {
        let lines = text.components(separatedBy: .newlines)
        var segments: [MarkdownSegment] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let level = headingLevel(for: trimmed) {
                let title = String(trimmed.drop(while: { $0 == "#" || $0 == " " }))
                segments.append(.heading(level: level, text: title))
                index += 1
                continue
            }

            if isThematicBreak(trimmed) {
                segments.append(.thematicBreak)
                index += 1
                continue
            }

            if let math = parseMathBlock(from: lines, start: index) {
                segments.append(math.segment)
                index = math.nextIndex
                continue
            }

            if let table = parseTable(from: lines, start: index) {
                segments.append(table.segment)
                index = table.nextIndex
                continue
            }

            if trimmed.hasPrefix(">") {
                let (quote, next) = collectBlockquote(from: lines, start: index)
                segments.append(.blockquote(quote))
                index = next
                continue
            }

            if let image = MarkdownImageParser.standaloneLine(trimmed) {
                segments.append(.image(alt: image.alt, url: image.url))
                index += 1
                continue
            }

            if listLineInfo(for: line) != nil {
                let (items, next) = collectListTree(from: lines, start: index)
                segments.append(.list(items))
                index = next
                continue
            }

            let (paragraph, next) = collectParagraph(from: lines, start: index)
            if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.paragraph(paragraph))
            }
            index = next
        }

        return segments
    }

    private static func headingLevel(for line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1 ... 6).contains(hashes) else { return nil }
        let remainder = line.dropFirst(hashes)
        guard remainder.first == " " else { return nil }
        return hashes
    }

    private static func parseMathBlock(from lines: [String], start: Int) -> (segment: MarkdownSegment, nextIndex: Int)? {
        let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
        if trimmed == #"\\["# {
            var parts: [String] = []
            var index = start + 1
            while index < lines.count {
                if lines[index].trimmingCharacters(in: .whitespaces) == #"\\]"# {
                    return (.mathBlock(parts.joined(separator: "\n")), index + 1)
                }
                parts.append(lines[index])
                index += 1
            }
            return nil
        }
        if trimmed == "$$" {
            var parts: [String] = []
            var index = start + 1
            while index < lines.count {
                if lines[index].trimmingCharacters(in: .whitespaces) == "$$" {
                    return (.mathBlock(parts.joined(separator: "\n")), index + 1)
                }
                parts.append(lines[index])
                index += 1
            }
            return nil
        }
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 {
            let inner = trimmed.dropFirst(2).dropLast(2)
            return (.mathBlock(String(inner)), start + 1)
        }
        return nil
    }

    private static func taskListMarker(in line: String) -> (checked: Bool, text: String)? {
        guard let marker = unorderedListMarker(in: line) else { return nil }
        let markerEnd = line.index(line.startIndex, offsetBy: marker.count)
        guard line[markerEnd...].hasPrefix("[") else { return nil }

        let stateIndex = line.index(after: markerEnd)
        guard stateIndex < line.endIndex else { return nil }
        let state = line[stateIndex]
        guard state == " " || state == "x" || state == "X" else { return nil }

        let closeIndex = line.index(after: stateIndex)
        guard closeIndex < line.endIndex, line[closeIndex] == "]" else { return nil }

        let spaceIndex = line.index(after: closeIndex)
        guard spaceIndex < line.endIndex, line[spaceIndex].isWhitespace else { return nil }

        let textStart = line[spaceIndex...].drop(while: \.isWhitespace).startIndex
        guard textStart < line.endIndex else { return nil }
        return (state != " ", String(line[textStart...]))
    }

    private static func listLineInfo(for line: String) -> (indent: Int, marker: MarkdownListMarker, text: String)? {
        let spaces = line.prefix(while: { $0 == " " }).count
        let indent = spaces / 2
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if let task = taskListMarker(in: trimmed) {
            return (indent, .task(checked: task.checked), task.text)
        }
        if let marker = unorderedListMarker(in: trimmed) {
            return (indent, .bullet, String(trimmed.dropFirst(marker.count)))
        }
        if orderedListMarker(in: trimmed) != nil, let dot = trimmed.firstIndex(of: ".") {
            let prefix = trimmed[..<dot]
            let number = Int(prefix) ?? 1
            let afterMarker = trimmed.index(dot, offsetBy: 1, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
            let contentStart = trimmed[afterMarker...].first == " "
                ? trimmed.index(after: afterMarker)
                : afterMarker
            return (indent, .ordered(number), String(trimmed[contentStart...]))
        }
        return nil
    }

    private static func collectListTree(from lines: [String], start: Int) -> ([MarkdownListItem], Int) {
        var parsed: [(indent: Int, marker: MarkdownListMarker, text: String)] = []
        var index = start
        while index < lines.count {
            guard let info = listLineInfo(for: lines[index]) else { break }
            parsed.append(info)
            index += 1
        }
        return (buildListTree(parsed: parsed, start: 0, parentIndent: -1).0, index)
    }

    private static func buildListTree(
        parsed: [(indent: Int, marker: MarkdownListMarker, text: String)],
        start: Int,
        parentIndent: Int
    ) -> ([MarkdownListItem], Int) {
        var items: [MarkdownListItem] = []
        var index = start
        while index < parsed.count {
            let entry = parsed[index]
            if parentIndent == -1 {
                guard entry.indent == 0 else { break }
            } else {
                guard entry.indent == parentIndent + 1 else { break }
            }

            var children: [MarkdownListItem] = []
            index += 1
            let childParent = parentIndent == -1 ? 0 : parentIndent + 1
            if index < parsed.count, parsed[index].indent > childParent {
                let built = buildListTree(parsed: parsed, start: index, parentIndent: childParent)
                children = built.0
                index = built.1
            }
            items.append(MarkdownListItem(marker: entry.marker, text: entry.text, children: children))
        }
        return (items, index)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        return stripped == "---" || stripped == "***" || stripped == "___"
    }

    private static func unorderedListMarker(in line: String) -> String? {
        let markers = ["- ", "* ", "+ "]
        for marker in markers where line.hasPrefix(marker) {
            return marker
        }
        return nil
    }

    private static func orderedListMarker(in line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dot]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber), line.index(after: dot) < line.endIndex else {
            return nil
        }
        let afterDot = line[line.index(after: dot)...]
        guard afterDot.first == " " else { return nil }
        return String(prefix) + ". "
    }

    private static func collectBlockquote(from lines: [String], start: Int) -> (String, Int) {
        var parts: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            let content = trimmed.dropFirst().drop(while: { $0 == ">" || $0 == " " })
            parts.append(String(content))
            index += 1
        }
        return (parts.joined(separator: "\n"), index)
    }

    private static func collectParagraph(from lines: [String], start: Int) -> (String, Int) {
        var parts: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            if headingLevel(for: trimmed) != nil
                || isThematicBreak(trimmed)
                || trimmed == "$$"
                || trimmed == #"\\["#
                || (trimmed.hasPrefix("$$") && trimmed.hasSuffix("$$"))
                || trimmed.hasPrefix(">")
                || listLineInfo(for: line) != nil
                || isTableRow(trimmed)
                || MarkdownImageParser.standaloneLine(trimmed) != nil {
                break
            }
            parts.append(line)
            index += 1
        }
        return (parts.joined(separator: "\n"), index)
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.contains("|")
    }

    private static func parseTable(from lines: [String], start: Int) -> (segment: MarkdownSegment, nextIndex: Int)? {
        guard start + 1 < lines.count else { return nil }
        let headerLine = lines[start].trimmingCharacters(in: .whitespaces)
        let separatorLine = lines[start + 1].trimmingCharacters(in: .whitespaces)
        guard isTableRow(headerLine), isTableSeparator(separatorLine) else { return nil }

        let headers = splitTableCells(headerLine)
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty || !isTableRow(line) { break }
            rows.append(splitTableCells(line))
            index += 1
        }
        return (.table(headers: headers, rows: rows), index)
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = splitTableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let stripped = cell.replacingOccurrences(of: " ", with: "")
            return !stripped.isEmpty && stripped.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" }
        }
    }

    private static func splitTableCells(_ line: String) -> [String] {
        var raw = line
        if raw.hasPrefix("|") { raw.removeFirst() }
        if raw.hasSuffix("|") { raw.removeLast() }
        return raw.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

// MARK: - Inline Markdown

private enum MarkdownInlineRenderer {
    static func attributedString(from source: String, baseFontSize: CGFloat) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.allowsExtendedAttributes = true
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.failurePolicy = .returnPartiallyParsedIfPossible

        let prepared = linkifyBareURLs(source)
        guard var attributed = try? AttributedString(markdown: prepared, options: options) else {
            return nil
        }

        for run in attributed.runs {
            var container = AttributeContainer()
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                container.font = .system(size: baseFontSize - 1, design: .monospaced)
                container.backgroundColor = Color.markdownRendererInlineCodeBackground
            } else if intent.contains(.stronglyEmphasized) && intent.contains(.emphasized) {
                container.font = .system(size: baseFontSize, weight: .semibold).italic()
            } else if intent.contains(.stronglyEmphasized) {
                container.font = .system(size: baseFontSize, weight: .semibold)
            } else if intent.contains(.emphasized) {
                container.font = .system(size: baseFontSize).italic()
            } else {
                container.font = .system(size: baseFontSize)
            }
            if intent.contains(.strikethrough) {
                container.strikethroughStyle = .single
            }
            attributed[run.range].mergeAttributes(container)
        }
        return attributed
    }

    private static func linkifyBareURLs(_ source: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\(\[])(https?://[^\s\)\]>]+)"#) else {
            return source
        }
        let nsRange = NSRange(source.startIndex..., in: source)
        var result = source
        for match in regex.matches(in: source, range: nsRange).reversed() {
            guard let range = Range(match.range(at: 1), in: result) else { continue }
            let url = String(result[range])
            result.replaceSubrange(range, with: "[\(url)](\(url))")
        }
        return result
    }
}

#if DEBUG
enum MarkdownPreviewSamples {
    static let demo = """
    ## 标题示例

    支持 **粗体**、*斜体*、`行内代码` 与 [链接](https://example.com)。

    - 无序列表第一项
    - 无序列表第二项

    1. 有序列表第一项
    2. 有序列表第二项

    > 这是一段引用文字。

    | 列 A | 列 B |
    | --- | --- |
    | 单元格 1 | 单元格 2 |

    ---
    """
}
#endif
