import SwiftUI
import AppKit
import UniformTypeIdentifiers
import WebKit

struct CanvasPreviewPayload: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let fileName: String
    let language: String
    let code: String

    init(title: String, language: String, code: String, fileName: String? = nil) {
        self.title = title
        self.language = language
        self.code = code
        self.fileName = fileName ?? CanvasPreviewSupport.fileName(title: title, language: language)
    }

    func isSameArtifact(as other: CanvasPreviewPayload) -> Bool {
        language == other.language && code == other.code
    }
}

struct OpenCanvasPreviewKey: EnvironmentKey {
    static let defaultValue: ((CanvasPreviewPayload) -> Void)? = nil
}

extension EnvironmentValues {
    var openCanvasPreview: ((CanvasPreviewPayload) -> Void)? {
        get { self[OpenCanvasPreviewKey.self] }
        set { self[OpenCanvasPreviewKey.self] = newValue }
    }
}

enum CanvasPreviewSupport {
    static let previewLanguages: Set<String> = [
        "html", "htm", "svg", "xml", "javascript", "js", "jsx", "tsx", "css"
    ]

    static func isPreviewable(_ language: String) -> Bool {
        previewLanguages.contains(language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func looksLikeSVG(_ code: String) -> Bool {
        code.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveContains("<svg")
    }

    static func looksLikeHTML(_ code: String) -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("<!doctype")
            || trimmed.hasPrefix("<html")
            || trimmed.contains("<body")
            || (trimmed.contains("<div") && trimmed.contains("</"))
    }

    static func inferLanguage(for code: String, fallback: String = "html") -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("<svg") { return "svg" }
        if trimmed.hasPrefix("<?xml") { return "xml" }
        if looksLikeHTML(code) { return "html" }
        return fallback
    }

  /// 拆分「说明文字 + 原始 SVG/HTML 标记」混排段落（模型常这样输出 Canvas 示例）
    static func splitTextAndMarkup(_ content: String) -> (text: String, markup: String, language: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(<!DOCTYPE|<html[\s>]|<svg[\s>])"#) else {
            return nil
        }
        let nsRange = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, range: nsRange),
              let markupStart = Range(match.range, in: content) else { return nil }

        let text = String(content[..<markupStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let markup = String(content[markupStart.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !markup.isEmpty else { return nil }
        return (text, markup, inferLanguage(for: markup))
    }

    static func shouldUseCanvasBlock(language: String, code: String) -> Bool {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if isPreviewable(normalized) { return true }
        if normalized.isEmpty || normalized == "plain text" || normalized == "text" {
            return looksLikeSVG(code) || looksLikeHTML(code)
        }
        return false
    }

    static func artifactTitle(language: String, code: String) -> String {
        if let title = firstMatch(in: code, pattern: #"(?is)<title[^>]*>(.*?)</title>"#) {
            let decoded = decodeHTML(title).trimmingCharacters(in: .whitespacesAndNewlines)
            if !decoded.isEmpty { return decoded }
        }

        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "svg", "xml": return "SVG Artifact"
        case "javascript", "js", "jsx", "tsx": return "Canvas Artifact"
        case "css": return "CSS Artifact"
        case "mermaid": return "Mermaid Artifact"
        default: return "HTML Artifact"
        }
    }

    static func fileName(title: String, language: String) -> String {
        var base = ""
        var lastWasDash = false

        for character in title.lowercased() {
            if character.isLetter || character.isNumber {
                base.append(character)
                lastWasDash = false
            } else if !lastWasDash {
                base.append("-")
                lastWasDash = true
            }
        }

        base = base.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "\(base.isEmpty ? "artifact" : base).\(fileExtension(for: language))"
    }

    static func fileExtension(for language: String) -> String {
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "svg", "xml": return "svg"
        case "javascript", "js", "jsx", "tsx": return "js"
        case "css": return "css"
        case "mermaid": return "mmd"
        default: return "html"
        }
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsRange),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

struct MermaidCodeBlockView: View {
    let code: String

    @Environment(\.openCanvasPreview) private var openCanvasPreview

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    var body: some View {
        if trimmedCode.isEmpty {
            CodeBlockView(language: "mermaid", code: code)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                previewSection
                CodeBlockView(
                    language: "mermaid",
                    code: code,
                    onOpenSidebar: openSidePanel
                )
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Mermaid 预览", systemImage: "chart.bar.doc.horizontal")
                .font(.system(size: AppLayout.captionSize, weight: .medium))
                .foregroundStyle(.secondary)

            MermaidDiagramView(source: code)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.chatBoxLine.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func openSidePanel() {
        openCanvasPreview?(
            CanvasPreviewPayload(title: "Mermaid 预览", language: "mermaid", code: code)
        )
    }
}

struct CanvasCodeBlockView: View {
    let language: String
    let code: String

    @Environment(\.openCanvasPreview) private var openCanvasPreview

    private var resolvedLanguage: String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return CanvasPreviewSupport.inferLanguage(for: code, fallback: "text")
        }
        return trimmed
    }

    private var canPreview: Bool {
        CanvasPreviewSupport.shouldUseCanvasBlock(language: resolvedLanguage, code: code)
            && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    var body: some View {
        if canPreview {
            CodeBlockView(
                language: resolvedLanguage,
                code: code,
                onOpenSidebar: openSideCanvas
            )
        } else {
            CodeBlockView(
                language: resolvedLanguage,
                code: code
            )
        }
    }

    private func openSideCanvas() {
        let payload = CanvasPreviewPayload(
            title: artifactTitle,
            language: resolvedLanguage,
            code: code,
            fileName: artifactFileName
        )
        openCanvasPreview?(payload)
    }

    private var artifactTitle: String {
        CanvasPreviewSupport.artifactTitle(language: resolvedLanguage, code: code)
    }

    private var artifactFileName: String {
        CanvasPreviewSupport.fileName(title: artifactTitle, language: resolvedLanguage)
    }
}

struct CanvasSidePanelView: View {
    let payload: CanvasPreviewPayload
    let onClose: () -> Void

    @State private var reloadID = UUID()
    @State private var previewError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            previewPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)

            Button {
                refreshPreview()
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("重新运行预览")

            Button {
                openInBrowser()
            } label: {
                Label("在浏览器打开", systemImage: "safari")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("在浏览器打开")

            Button {
                copyToPasteboard(payload.code)
            } label: {
                Label("复制", systemImage: "square.on.square")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("复制代码")

            Button {
                saveCode()
            } label: {
                Label("保存", systemImage: "arrow.down")
                    .labelStyle(.iconOnly)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("保存代码")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var previewPane: some View {
        ZStack(alignment: .top) {
            CanvasPreviewWebView(
                html: MarkdownWebTemplate.canvasPreviewDocument(language: payload.language, code: payload.code),
                language: payload.language,
                reloadID: reloadID,
                errorMessage: $previewError
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, previewError == nil ? 0 : 38)

            if let previewError {
                previewErrorBanner(previewError)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func previewErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: AppLayout.captionSize))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .zIndex(1)
    }

    private func saveCode() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = payload.fileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? payload.code.write(to: url, atomically: true, encoding: .utf8)
    }

    private func refreshPreview() {
        previewError = nil
        reloadID = UUID()
    }

    private func openInBrowser() {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ChatBoxesCanvasPreviews", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let browserFileName = CanvasPreviewSupport.fileName(title: payload.title, language: "html")
            let url = directory.appendingPathComponent(browserFileName)
            let html = MarkdownWebTemplate.canvasPreviewDocument(language: payload.language, code: payload.code)
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            previewError = error.localizedDescription
        }
    }

    private var fileExtension: String {
        CanvasPreviewSupport.fileExtension(for: payload.language)
    }

    private var contentType: UTType {
        switch fileExtension {
        case "svg": return .svg
        case "js": return .javaScript
        case "css": return .css
        case "mmd": return .plainText
        default: return .html
        }
    }
}

private struct CanvasPreviewWebView: NSViewRepresentable {
    let html: String
    let language: String
    let reloadID: UUID
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(errorMessage: $errorMessage)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "previewError")
        configuration.userContentController.add(context.coordinator, name: "height")
        configuration.userContentController.addUserScript(WKUserScript(
            source: """
            window.addEventListener('error', function(event) {
              window.webkit.messageHandlers.previewError.postMessage(event.message || '预览运行失败');
            });
            window.addEventListener('unhandledrejection', function(event) {
              const reason = event.reason && (event.reason.message || String(event.reason));
              window.webkit.messageHandlers.previewError.postMessage(reason || 'Promise 运行失败');
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.errorMessage = $errorMessage
        let signature = "\(reloadID)|\(language)|\(html.count)|\(html.hashValue)"
        guard context.coordinator.lastSignature != signature else { return }
        context.coordinator.lastSignature = signature
        errorMessage = nil
        webView.loadHTMLString(html, baseURL: URL(string: "https://chatboxes.local/"))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastSignature = ""
        var errorMessage: Binding<String?>

        init(errorMessage: Binding<String?>) {
            self.errorMessage = errorMessage
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "previewError" else { return }
            if let text = message.body as? String, !text.isEmpty {
                errorMessage.wrappedValue = text
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            errorMessage.wrappedValue = error.localizedDescription
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            errorMessage.wrappedValue = error.localizedDescription
        }
    }
}

