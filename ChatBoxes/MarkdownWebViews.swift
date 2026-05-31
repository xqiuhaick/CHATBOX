import AppKit
import SwiftUI
import WebKit

// MARK: - Image

enum MarkdownImageParser {
    static func standaloneLine(_ line: String) -> (alt: String, url: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseImageToken(trimmed, fullLineOnly: true)
    }

    static func parseImageToken(_ token: String, fullLineOnly: Bool = false) -> (alt: String, url: String)? {
        guard token.hasPrefix("![") else { return nil }
        guard let closeBracket = token.firstIndex(of: "]"),
              token.index(after: closeBracket) < token.endIndex,
              token[token.index(after: closeBracket)] == "(",
              let closeParen = token.lastIndex(of: ")"),
              closeParen > closeBracket else { return nil }

        let alt = String(token[token.index(token.startIndex, offsetBy: 2)..<closeBracket])
        let urlStart = token.index(after: closeBracket)
        let url = String(token[token.index(after: urlStart)..<closeParen]).trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return nil }

        if fullLineOnly {
            let suffix = token[token.index(after: closeParen)...].trimmingCharacters(in: .whitespaces)
            guard suffix.isEmpty else { return nil }
        }
        return (alt, url)
    }
}

struct MarkdownImageView: View {
    let alt: String
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString), !urlString.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 480, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }
                        .help(alt.isEmpty ? urlString : alt)
                case .failure:
                    imagePlaceholder(label: alt.isEmpty ? "图片加载失败" : alt)
                case .empty:
                    ProgressView()
                        .frame(width: 120, height: 80)
                @unknown default:
                    EmptyView()
                }
            }
        } else {
            imagePlaceholder(label: alt.isEmpty ? "无效图片链接" : alt)
        }
    }

    private func imagePlaceholder(label: String) -> some View {
        Label(label, systemImage: "photo")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(12)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MarkdownCitationChip: View {
    let index: Int
    let baseFontSize: CGFloat

    @Environment(\.markdownSearchResults) private var searchResults

    private var result: WebSearchResultItem? {
        guard index > 0, index <= searchResults.count else { return nil }
        return searchResults[index - 1]
    }

    var body: some View {
        Button {
            if let urlString = result?.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text("\(index)")
                .font(.system(size: max(10, baseFontSize - 3), weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(result?.title ?? "来源 \(index)")
    }
}

// MARK: - Shared Web Embed

struct MarkdownWebEmbedView: View {
    let html: String
    var minHeight: CGFloat = 24
    var maxHeight: CGFloat = 800

    @State private var contentHeight: CGFloat = 48
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        MarkdownWebViewRepresentable(
            html: html,
            colorScheme: colorScheme,
            contentHeight: $contentHeight
        )
        .frame(height: min(max(contentHeight, minHeight), maxHeight))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownWebViewRepresentable: NSViewRepresentable {
    let html: String
    let colorScheme: ColorScheme
    @Binding var contentHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $contentHeight)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "height")
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.enclosingScrollView?.hasVerticalScroller = false
        webView.enclosingScrollView?.hasHorizontalScroller = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $contentHeight
        let signature = "\(colorScheme)|\(html.count)|\(html.hashValue)"
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature
        webView.loadHTMLString(html, baseURL: URL(string: "https://chatboxes.local/"))
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        var lastSignature: String = ""

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "height",
                  let value = message.body as? Double else { return }
            height.wrappedValue = CGFloat(max(24, value))
        }
    }
}

// MARK: - Specialized Blocks

struct MermaidDiagramView: View {
    let source: String

    var body: some View {
        MarkdownWebEmbedView(html: MarkdownWebTemplate.mermaid(source: source), minHeight: 80, maxHeight: 520)
    }
}

struct KaTeXBlockView: View {
    let latex: String
    var displayMode: Bool = true

    var body: some View {
        MarkdownWebEmbedView(
            html: MarkdownWebTemplate.katex(latex: latex, displayMode: displayMode),
            minHeight: displayMode ? 40 : 24,
            maxHeight: displayMode ? 400 : 80
        )
    }
}

struct MarkdownHTMLPreviewBlock: View {
    let html: String

    var body: some View {
        MarkdownWebEmbedView(html: MarkdownWebTemplate.htmlDocument(body: html), minHeight: 60, maxHeight: 600)
    }
}

struct MarkdownHTMLInlineView: View {
    let html: String
    let baseFontSize: CGFloat

    var body: some View {
        MarkdownWebEmbedView(
            html: MarkdownWebTemplate.htmlInline(body: html, fontSize: baseFontSize),
            minHeight: 22,
            maxHeight: 200
        )
    }
}

// MARK: - Mixed Inline (text + math + HTML)

struct MarkdownMixedInlineView: View {
    let source: String
    let baseFontSize: CGFloat

    private var parts: [MarkdownInlinePart] {
        MarkdownInlinePartParser.parse(source)
    }

    var body: some View {
        if parts.count == 1, case .text(let text) = parts[0] {
            MarkdownRichInlineText(text: text, baseFontSize: baseFontSize)
        } else {
            FlowLayout(spacing: 2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    partView(part)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func partView(_ part: MarkdownInlinePart) -> some View {
        switch part {
        case .text(let text):
            MarkdownRichInlineText(text: text, baseFontSize: baseFontSize)
        case .mathInline(let latex):
            KaTeXBlockView(latex: latex, displayMode: false)
                .frame(minWidth: 20)
        case .html(let snippet):
            MarkdownHTMLInlineView(html: snippet, baseFontSize: baseFontSize)
        case .image(let alt, let url):
            MarkdownImageView(alt: alt, urlString: url)
        case .citation(let index):
            MarkdownCitationChip(index: index, baseFontSize: baseFontSize)
        }
    }
}

enum MarkdownInlinePart {
    case text(String)
    case mathInline(String)
    case html(String)
    case image(alt: String, url: String)
    case citation(index: Int)
}

enum MarkdownInlinePartParser {
    static func parse(_ source: String) -> [MarkdownInlinePart] {
        guard !source.isEmpty else { return [] }

        var parts: [MarkdownInlinePart] = []
        var index = source.startIndex

        while index < source.endIndex {
            if let mathRange = findInlineMath(in: source, from: index) {
                if mathRange.lowerBound > index {
                    appendText(String(source[index..<mathRange.lowerBound]), to: &parts)
                }
                let latex = extractLatexToken(from: source, range: mathRange)
                parts.append(.mathInline(latex))
                index = mathRange.upperBound
                continue
            }

            if let image = findImage(in: source, from: index) {
                if image.range.lowerBound > index {
                    appendText(String(source[index..<image.range.lowerBound]), to: &parts)
                }
                parts.append(.image(alt: image.alt, url: image.url))
                index = image.range.upperBound
                continue
            }

            if let citation = findCitation(in: source, from: index) {
                if citation.range.lowerBound > index {
                    appendText(String(source[index..<citation.range.lowerBound]), to: &parts)
                }
                parts.append(.citation(index: citation.index))
                index = citation.range.upperBound
                continue
            }

            if let htmlRange = findHTMLSnippet(in: source, from: index) {
                if htmlRange.lowerBound > index {
                    appendText(String(source[index..<htmlRange.lowerBound]), to: &parts)
                }
                parts.append(.html(String(source[htmlRange])))
                index = htmlRange.upperBound
                continue
            }

            appendText(String(source[index...]), to: &parts)
            break
        }

        return parts.isEmpty ? [.text(source)] : parts
    }

    private static func extractLatexToken(from source: String, range: Range<String.Index>) -> String {
        let token = String(source[range])
        if token.hasPrefix(#"\("#) {
            return String(token.dropFirst(2).dropLast(2))
        }
        return String(token.dropFirst().dropLast())
    }

    private static func appendText(_ text: String, to parts: inout [MarkdownInlinePart]) {
        guard !text.isEmpty else { return }
        if case .text(let existing)? = parts.last {
            parts[parts.count - 1] = .text(existing + text)
        } else {
            parts.append(.text(text))
        }
    }

    private static func findInlineMath(in source: String, from start: String.Index) -> Range<String.Index>? {
        if start < source.endIndex, source[start] == "$" {
            let afterFirst = source.index(after: start)
            guard afterFirst < source.endIndex, source[afterFirst] != "$" else { return nil }
            var index = afterFirst
            while index < source.endIndex {
                if source[index] == "$" {
                    return start..<source.index(after: index)
                }
                index = source.index(after: index)
            }
            return nil
        }

        if source[start...].hasPrefix(#"\("#) {
            guard let close = source.range(of: #"\)"#, range: start..<source.endIndex) else { return nil }
            return start..<close.upperBound
        }
        return nil
    }

    private static func findImage(in source: String, from start: String.Index) -> (range: Range<String.Index>, alt: String, url: String)? {
        guard start < source.endIndex, source[start] == "!" else { return nil }
        guard let closeBracket = source[start...].firstIndex(of: "]") else { return nil }
        let afterBracket = source.index(after: closeBracket)
        guard afterBracket < source.endIndex, source[afterBracket] == "(" else { return nil }
        guard let closeParen = source[afterBracket...].firstIndex(of: ")") else { return nil }
        let tokenStart = start
        let tokenEnd = source.index(after: closeParen)
        let token = String(source[tokenStart..<tokenEnd])
        guard let parsed = MarkdownImageParser.parseImageToken(token) else { return nil }
        return (tokenStart..<tokenEnd, parsed.alt, parsed.url)
    }

    private static func findCitation(in source: String, from start: String.Index) -> (range: Range<String.Index>, index: Int)? {
        guard start < source.endIndex, source[start] == "[" else { return nil }
        return CitationScan(source: source, start: start).scan()
    }

    private struct CitationScan {
        let source: String
        let start: String.Index

        func scan() -> (range: Range<String.Index>, index: Int)? {
            var index = source.index(after: start)
            var digits = ""
            while index < source.endIndex, source[index].isNumber {
                digits.append(source[index])
                index = source.index(after: index)
            }
            guard !digits.isEmpty, index < source.endIndex, source[index] == "]" else { return nil }
            let afterBracket = source.index(after: index)
            if afterBracket < source.endIndex, source[afterBracket] == "(" { return nil }
            guard let number = Int(digits) else { return nil }
            return (start..<afterBracket, number)
        }
    }

    private static let inlineHTMLTags: Set<String> = ["mark", "sup", "sub", "strong", "em", "b", "i", "u", "small", "span", "del", "ins"]

    private static func findHTMLSnippet(in source: String, from start: String.Index) -> Range<String.Index>? {
        guard start < source.endIndex, source[start] == "<" else { return nil }
        guard let openEnd = source[start...].firstIndex(of: ">") else { return nil }
        let openTag = String(source[start...openEnd])
        let openClose = source.index(after: openEnd)

        if openTag.hasSuffix("/>") {
            return start..<openClose
        }

        guard let tagName = parseTagName(from: openTag),
              inlineHTMLTags.contains(tagName.lowercased()) else {
            return start..<openClose
        }

        let closePattern = "</\(tagName)>"
        if let closeRange = source[openClose...].range(of: closePattern, options: .caseInsensitive) {
            return start..<closeRange.upperBound
        }
        return start..<openClose
    }

    private static func parseTagName(from openTag: String) -> String? {
        let trimmed = openTag.dropFirst().trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, first.isLetter else { return nil }
        var name = ""
        for char in trimmed {
            if char.isLetter || char.isNumber { name.append(char) } else { break }
        }
        return name.isEmpty ? nil : name
    }
}

// MARK: - HTML Templates

enum MarkdownWebTemplate {
    private static let katexCSS = "https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css"
    private static let katexJS = "https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"
    private static let mermaidJS = "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.min.js"

    static func mermaid(source: String) -> String {
        let encoded = encodeBase64(source)
        return wrapBody("""
        <div id="diagram"></div>
        <script src="\(mermaidJS)"></script>
        <script>
        (async function() {
          try {
            const raw = decodeURIComponent(escape(atob('\(encoded)')));
            mermaid.initialize({ startOnLoad: false, theme: 'neutral', securityLevel: 'strict' });
            const { svg } = await mermaid.render('mmd-' + Date.now(), raw);
            document.getElementById('diagram').innerHTML = svg;
          } catch (e) {
            document.getElementById('diagram').textContent = e.message || 'Mermaid 渲染失败';
          }
          reportHeight();
        })();
        </script>
        """)
    }

    static func katex(latex: String, displayMode: Bool) -> String {
        let encoded = encodeBase64(latex)
        let mode = displayMode ? "true" : "false"
        return wrapBody("""
        <div id="math"></div>
        <link rel="stylesheet" href="\(katexCSS)">
        <script src="\(katexJS)"></script>
        <script>
        (function() {
          try {
            const raw = decodeURIComponent(escape(atob('\(encoded)')));
            katex.render(raw, document.getElementById('math'), { displayMode: \(mode), throwOnError: false });
          } catch (e) {
            document.getElementById('math').textContent = decodeURIComponent(escape(atob('\(encoded)')));
          }
          reportHeight();
        })();
        </script>
        """)
    }

    static func htmlDocument(body: String) -> String {
        wrapBody(sanitizeHTML(body))
    }

    static func canvasPreviewDocument(language: String, code: String) -> String {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "svg", "xml":
            if trimmed.lowercased().hasPrefix("<svg") || trimmed.lowercased().hasPrefix("<?xml") {
                return wrapCanvasDocument(sanitizeCanvasHTML(trimmed), contentMode: "center")
            }
            return wrapCanvasDocument("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 400 300\">\(sanitizeCanvasHTML(trimmed))</svg>", contentMode: "center")
        case "css":
            return wrapCanvasDocument("""
            <div id="canvas-root" class="canvas-demo">
              <p>CSS 预览</p>
              <div class="demo">示例元素</div>
            </div>
            <style>\(sanitizeCanvasHTML(trimmed))</style>
            """, contentMode: "document")
        case "javascript", "js", "jsx", "tsx":
            let encoded = encodeBase64(trimmed)
            return wrapCanvasDocument("""
            <div id="canvas-root" class="canvas-root"></div>
            <script>
            (function() {
              try {
                const raw = decodeURIComponent(escape(atob('\(encoded)')));
                const fn = new Function(raw);
                fn();
              } catch (e) {
                const message = e.message || '脚本执行失败';
                document.getElementById('canvas-root').textContent = message;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.previewError) {
                  window.webkit.messageHandlers.previewError.postMessage(message);
                }
              }
            })();
            </script>
            """, contentMode: "document")
        case "html", "htm":
            if trimmed.lowercased().contains("<html") || trimmed.lowercased().contains("<!doctype") {
                return normalizeCanvasHTMLDocument(sanitizeCanvasHTML(trimmed))
            }
            return wrapCanvasDocument(sanitizeCanvasHTML(trimmed), contentMode: "document")
        case "mermaid":
            return mermaid(source: trimmed)
        default:
            if CanvasPreviewSupport.looksLikeSVG(trimmed) {
                return canvasPreviewDocument(language: "svg", code: trimmed)
            }
            if CanvasPreviewSupport.looksLikeHTML(trimmed) {
                return canvasPreviewDocument(language: "html", code: trimmed)
            }
            return wrapCanvasDocument("<pre class=\"plain-text-preview\">\(escapeHTML(trimmed))</pre>", contentMode: "document")
        }
    }

    static func htmlInline(body: String, fontSize: CGFloat) -> String {
        wrapBody("""
        <div style="font-size:\(fontSize)px;line-height:1.45">\(sanitizeHTML(body))</div>
        """)
    }

    private static func wrapBody(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body {
            margin: 0;
            padding: 4px 2px;
            background: transparent;
            color: #1d1d1f;
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            overflow: hidden;
          }
          @media (prefers-color-scheme: dark) {
            html, body { color: #f5f5f7; }
          }
          img { max-width: 100%; height: auto; }
          table { border-collapse: collapse; width: 100%; }
          th, td { border: 1px solid rgba(127,127,127,0.35); padding: 6px 8px; }
          pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.92em; }
          pre { background: rgba(127,127,127,0.12); padding: 8px; border-radius: 8px; overflow-x: auto; }
          a { color: #007aff; }
          svg { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>
        \(body)
        <script>
        function reportHeight() {
          const h = Math.ceil(document.documentElement.scrollHeight);
          window.webkit.messageHandlers.height.postMessage(h);
        }
        window.addEventListener('load', function() { setTimeout(reportHeight, 80); });
        </script>
        </body>
        </html>
        """
    }

    private static func wrapCanvasDocument(_ body: String, contentMode: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(canvasBaseStyle(contentMode: contentMode))
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    private static func normalizeCanvasHTMLDocument(_ html: String) -> String {
        var document = html
        if document.range(of: "<meta\\s+name=[\"']viewport[\"']", options: [.regularExpression, .caseInsensitive]) == nil {
            document = insertIntoHead("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">", in: document)
        }
        document = insertIntoHead(canvasBaseStyle(contentMode: "document"), in: document)
        return document
    }

    private static func insertIntoHead(_ markup: String, in html: String) -> String {
        if let headEnd = html.range(of: "</head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: "\n\(markup)\n", at: headEnd.lowerBound)
            return result
        }
        if let htmlStartEnd = html.range(of: "<html[^>]*>", options: [.regularExpression, .caseInsensitive])?.upperBound {
            var result = html
            result.insert(contentsOf: "\n<head>\(markup)</head>\n", at: htmlStartEnd)
            return result
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        \(markup)
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    private static func canvasBaseStyle(contentMode: String) -> String {
        let bodyDisplay = contentMode == "center" ? "display: grid; place-items: center;" : "display: block;"
        return """
        <style id="chatboxes-canvas-base">
          :root { color-scheme: light dark; }
          html, body {
            width: 100%;
            min-height: 100%;
            margin: 0;
            background: transparent;
            color: CanvasText;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          }
          body {
            box-sizing: border-box;
            padding: 24px;
            \(bodyDisplay)
          }
          *, *::before, *::after { box-sizing: border-box; }
          img, video, canvas, svg {
            max-width: 100%;
            height: auto;
          }
          svg {
            display: block;
            max-height: calc(100vh - 48px);
          }
          canvas {
            border-radius: 6px;
          }
          .canvas-root, .canvas-demo {
            width: 100%;
            min-height: calc(100vh - 48px);
          }
          .plain-text-preview {
            margin: 0;
            white-space: pre-wrap;
            overflow-wrap: anywhere;
            font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
            font-size: 13px;
            line-height: 1.5;
          }
        </style>
        """
    }

    private static func encodeBase64(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }


    static func sanitizeCanvasHTML(_ html: String) -> String {
        var result = html
        let blocked = ["iframe", "object", "embed"]
        for tag in blocked {
            result = result.replacingOccurrences(
                of: "(?i)<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: "(?i)<\(tag)[^>]*/?>",
                with: "",
                options: .regularExpression
            )
        }
        result = result.replacingOccurrences(of: "(?i)<form\\b([^>]*)>", with: "<div data-blocked-form$1>", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)</form>", with: "</div>", options: .regularExpression)
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func sanitizeHTML(_ html: String) -> String {
        var result = html
        let blocked = ["script", "iframe", "object", "embed", "form", "input", "button", "link", "meta", "style"]
        for tag in blocked {
            result = result.replacingOccurrences(
                of: "(?i)<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: "",
                options: .regularExpression
            )
            result = result.replacingOccurrences(
                of: "(?i)<\(tag)[^>]*/?>",
                with: "",
                options: .regularExpression
            )
        }
        result = result.replacingOccurrences(of: "(?i)on\\w+\\s*=", with: "data-blocked=", options: .regularExpression)
        result = result.replacingOccurrences(of: "(?i)javascript:", with: "blocked:", options: .regularExpression)
        return result
    }
}
