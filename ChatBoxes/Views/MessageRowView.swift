import AppKit
import MapKit
import SwiftUI
import UniformTypeIdentifiers

struct MessageRowView: View {
    @Environment(ChatStore.self) private var store
    let message: ChatMessage
    let onRegenerate: () -> Void

    @State private var showThinkingPopover = false
    @State private var showMapDetail = false
    @State private var showWeatherDetail = false

    private var feedbackStore: MessageFeedbackStore { MessageFeedbackStore.shared }

    private var feedback: MessageFeedbackValue? {
        feedbackStore.feedback(for: message.id)
    }

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantContent
        case .system:
            EmptyView()
        }
    }

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 8) {
                if let image = imageFromDataURL(message.imageDataURL) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !message.content.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(message.content)
                            .font(.system(size: AppLayout.bodySize))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(Color.chatBoxUserBubble, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        if store.settings.showMessageTimestamps {
                            Text(formatTimestamp(message.createdAt))
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                if let fileName = message.fileName, !fileName.isEmpty {
                    Label(fileName, systemImage: "doc")
                        .font(.system(size: AppLayout.captionSize))
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu {
                Button("复制") { copyToPasteboard(message.content) }
                Button("重新编辑问题") { store.requestModify(message.content) }
            }
        }
    }

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let status = thinkingStatusText {
                ThinkingStatusLabel(
                    text: status,
                    isShimmerActive: isThinkingShimmerActive,
                    showsChevron: shouldShowThinkingChevron,
                    onTap: shouldShowThinkingDetails ? { showThinkingPopover = true } : nil
                )
                .popover(isPresented: $showThinkingPopover, arrowEdge: .top) {
                    ThinkingDetailSheet(message: message)
                }
            }

            messageBody

            if shouldShowActions {
                messageActions
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showMapDetail) {
            if let card = message.mapCard {
                PlaceDetailSheet(mapCard: card, detailText: message.content)
            }
        }
        .sheet(isPresented: $showWeatherDetail) {
            if let card = message.weatherCard {
                WeatherDetailSheet(weatherCard: card, detailText: message.content)
            }
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        if message.messageType == .mapCard, let card = message.mapCard {
            MapCardView(card: card) {
                showMapDetail = true
            }
        } else if message.messageType == .weatherCard, let card = message.weatherCard {
            WeatherCardView(card: card, detailText: message.content) {
                showWeatherDetail = true
            }
        } else if message.messageType == .imageCard {
            GeneratedImageCard(
                prompt: message.content,
                imageDataURL: message.imageDataURL,
                isGenerating: message.generating == true,
                isError: message.error == true
            )
        } else if !message.content.isEmpty {
            MarkdownMessageView(
                text: message.content,
                isGenerating: message.generating == true,
                isError: message.error == true,
                searchResults: message.searchResults ?? []
            )
        } else if message.error == true {
            Text("生成失败")
                .font(.system(size: AppLayout.bodySize))
                .foregroundStyle(.secondary)
        }
    }

    private var shouldShowThinkingChevron: Bool {
        shouldShowThinkingDetails && !isThinkingShimmerActive
    }

    private var thinkingStatusText: String? {
        if message.searchInProgress == true { return "正在搜索" }
        if message.generating == true, message.content.isEmpty { return "正在思考" }
        if message.reasoningDurationSec != nil || !(message.reasoningContent ?? "").isEmpty {
            return reasoningDurationTitle(seconds: message.reasoningDurationSec)
        }
        if !(message.searchResults ?? []).isEmpty { return "已搜索网页" }
        return nil
    }

    private var isThinkingShimmerActive: Bool {
        message.searchInProgress == true
            || (message.generating == true && message.content.isEmpty)
    }

    private var shouldShowThinkingDetails: Bool {
        message.searchInProgress == true
            || (message.generating == true && message.content.isEmpty)
            || !(message.reasoningContent ?? "").isEmpty
            || message.reasoningDurationSec != nil
            || !(message.searchSummary ?? "").isEmpty
            || !(message.searchResults ?? []).isEmpty
    }

    private var shouldShowActions: Bool {
        message.generating != true && !message.content.isEmpty && message.messageType != .imageCard
    }

    private var messageActions: some View {
        HStack(spacing: 2) {
            actionButton("square.on.square", "复制") {
                copyToPasteboard(assistantCopyText)
            }
            actionButton("speaker.wave.2", "朗读") {
                Task { try? await store.speakText(assistantCopyText) }
            }
            actionButton(feedback == .up ? "hand.thumbsup.fill" : "hand.thumbsup", "有帮助") {
                feedbackStore.toggle(.up, for: message.id)
            }
            actionButton(feedback == .down ? "hand.thumbsdown.fill" : "hand.thumbsdown", "没帮助") {
                feedbackStore.toggle(.down, for: message.id)
            }
            Menu {
                ShareLink(item: assistantCopyText) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }
                Button("重新生成", action: onRegenerate)
                Button("复制全文") { copyToPasteboard(assistantCopyText) }
                Button("导出为文件…") { exportMessage() }
                if shouldShowThinkingDetails {
                    Button("查看思考过程") { showThinkingPopover = true }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .help("更多")
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }

    private var assistantCopyText: String {
        message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func actionButton(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func exportMessage() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "message.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? message.content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func imageFromDataURL(_ value: String?) -> Image? {
        guard let value, value.hasPrefix("data:"),
              let comma = value.firstIndex(of: ",") else { return nil }
        let base64 = String(value[value.index(after: comma)...])
        guard let data = Data(base64Encoded: base64),
              let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
    }

    private func formatTimestamp(_ ms: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}

struct MarkdownMessageView: View {
    let text: String
    let isGenerating: Bool
    var isError: Bool = false
    var searchResults: [WebSearchResultItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .code(let language, let code):
                    markdownCodeBlockView(language: language, code: code)
                case .text(let content):
                    MarkdownHTMLBlock(
                        text: content,
                        baseFontSize: AppLayout.bodySize,
                        expandToWidth: true,
                        searchResults: searchResults
                    )
                }
            }
        }
        .foregroundStyle(isError ? Color.secondary : Color.primary)
    }
}

private struct GeneratedImageCard: View {
    let prompt: String
    let imageDataURL: String?
    let isGenerating: Bool
    let isError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isGenerating {
                VStack(alignment: .leading, spacing: 18) {
                    Text("正在创建图片")
                        .font(.system(size: AppLayout.bodySize, weight: .medium))
                        .foregroundStyle(.secondary)
                    ImageCreationDots()
                        .frame(maxWidth: .infinity, minHeight: 250)
                }
                .padding(20)
                .frame(width: 300, height: 360)
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            } else if let image = imageFromDataURL(imageDataURL) {
                VStack(alignment: .leading, spacing: 10) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 360, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    HStack(spacing: 4) {
                        imageActionButton("square.on.square", "复制提示词") {
                            copyToPasteboard(prompt)
                        }
                        imageActionButton("arrow.down", "保存图片") {
                            saveImage()
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            } else {
                Text(isError ? prompt : "图片生成失败")
                    .font(.system(size: AppLayout.bodySize))
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func imageActionButton(_ systemName: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func saveImage() {
        guard let data = imageData(from: imageDataURL) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "generated-image.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func imageFromDataURL(_ value: String?) -> Image? {
        guard let data = imageData(from: value),
              let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
    }

    private func imageData(from value: String?) -> Data? {
        guard let value, value.hasPrefix("data:"),
              let comma = value.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...]))
    }
}

private struct ImageCreationDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            VStack(spacing: 18) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 24) {
                        ForEach(0..<4, id: \.self) { column in
                            let distance = abs(Double(row - 2)) + abs(Double(column - 1))
                            let pulse = (sin(phase * 2.4 - distance * 0.45) + 1) / 2
                            Circle()
                                .fill(Color.secondary.opacity(0.16 + pulse * 0.42))
                                .frame(width: 3 + CGFloat(pulse) * 5, height: 3 + CGFloat(pulse) * 5)
                        }
                    }
                }
            }
        }
    }
}

private enum MarkdownBlock {
    case text(String)
    case code(language: String, code: String)
}

private func parseBlocks(_ text: String) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    let pattern = #"```([^\n]*)\n?([\s\S]*?)```"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return blocksForUnclosedFence(in: text) ?? [.text(text)]
    }

    let nsRange = NSRange(text.startIndex..., in: text)
    var lastEnd = text.startIndex

    regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
        guard let match, let fullRange = Range(match.range, in: text) else { return }
        if lastEnd < fullRange.lowerBound {
            appendTextSegment(String(text[lastEnd..<fullRange.lowerBound]), to: &blocks)
        }
        let lang = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
        let code = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
        blocks.append(.code(language: lang, code: code))
        lastEnd = fullRange.upperBound
    }

    if lastEnd < text.endIndex {
        appendTrailingSegment(String(text[lastEnd...]), to: &blocks)
    }

    if blocks.isEmpty {
        return blocksForUnclosedFence(in: text) ?? [.text(text)]
    }
    return blocks
}

private func appendTextSegment(_ segment: String, to blocks: inout [MarkdownBlock]) {
    guard !segment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    blocks.append(.text(segment))
}

private func appendTrailingSegment(_ segment: String, to blocks: inout [MarkdownBlock]) {
    if let openFence = parseOpenFenceSegment(segment) {
        let prefix = segment.prefix(segment.count - openFence.suffixLength)
        appendTextSegment(String(prefix), to: &blocks)
        blocks.append(.code(language: openFence.language, code: openFence.code))
        return
    }
    appendTextSegment(segment, to: &blocks)
}

private struct OpenFenceSegment {
    let language: String
    let code: String
    let suffixLength: Int
}

/// 流式输出尚未闭合的 ``` 时，按代码块渲染，避免整段 HTML 进 WebView 撑出巨大空白。
private func parseOpenFenceSegment(_ segment: String) -> OpenFenceSegment? {
    guard let fenceStart = segment.range(of: "```") else { return nil }
    let tail = segment[fenceStart.lowerBound...]
    guard tail.hasPrefix("```") else { return nil }

    let afterMarker = tail.index(tail.startIndex, offsetBy: 3)
    let remainder = String(tail[afterMarker...])
    if let newline = remainder.firstIndex(of: "\n") {
        let language = String(remainder[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
        let code = String(remainder[remainder.index(after: newline)...])
        return OpenFenceSegment(language: language, code: code, suffixLength: tail.count)
    }
    return OpenFenceSegment(language: remainder.trimmingCharacters(in: .whitespacesAndNewlines), code: "", suffixLength: tail.count)
}

private func blocksForUnclosedFence(in text: String) -> [MarkdownBlock]? {
    guard let openFence = parseOpenFenceSegment(text) else { return nil }
    var blocks: [MarkdownBlock] = []
    let prefix = text.prefix(text.count - openFence.suffixLength)
    appendTextSegment(String(prefix), to: &blocks)
    blocks.append(.code(language: openFence.language, code: openFence.code))
    return blocks
}

@ViewBuilder
private func markdownCodeBlockView(language: String, code: String) -> some View {
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "mermaid":
        MermaidCodeBlockView(code: code)
    case "math", "latex", "katex", "tex":
        KaTeXBlockView(latex: code, displayMode: true)
    case "html", "htm", "svg", "xml", "javascript", "js", "jsx", "tsx", "css":
        CanvasCodeBlockView(language: language, code: code)
    default:
        if CanvasPreviewSupport.shouldUseCanvasBlock(language: language, code: code) {
            CanvasCodeBlockView(language: language, code: code)
        } else {
            CodeBlockView(language: language, code: code)
        }
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    var onOpenSidebar: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "Plain text" : language)
                    .font(.system(size: AppLayout.captionSize))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onOpenSidebar {
                    Button(action: onOpenSidebar) {
                        Label("预览", systemImage: "play.fill")
                            .font(.system(size: AppLayout.captionSize))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("预览")
                    .padding(.trailing, 10)
                }
                Button {
                    copyToPasteboard(code)
                } label: {
                    Label("复制", systemImage: "square.on.square")
                        .font(.system(size: AppLayout.captionSize))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(CodeHighlighter.highlight(code: code, language: language))
                    .font(.system(size: AppLayout.codeSize, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.chatBoxLine.opacity(0.35), lineWidth: 0.5)
        )
    }
}

struct MapCardView: View {
    let card: MapCardPayload
    var onTap: (() -> Void)? = nil

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: card.latitude, longitude: card.longitude)
    }

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 0) {
                mapPreview
                detailsPanel
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.chatBoxLine.opacity(0.35), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var mapPreview: some View {
        ZStack {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            ))) {
                Marker(card.title, coordinate: coordinate)
            }
            .allowsHitTesting(false)

            VStack(spacing: 6) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }
            .padding(.bottom, 36)

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    Text("Legal")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.9))
                    Spacer()
                    HStack(spacing: 8) {
                        Label("地图预览", systemImage: "map")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                        Text("Apple 地图")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
            }
        }
        .frame(height: 188)
    }

    private var detailsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text(card.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let rating = card.rating {
                    mapRatingBadge(rating)
                }
            }

            if let subtitle = card.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let hours = card.openingHours, !hours.isEmpty {
                mapInfoRow(icon: "clock", text: hours)
            }
            if let address = card.address, !address.isEmpty {
                mapInfoRow(icon: "mappin.and.ellipse", text: address)
            }
            if let website = card.website, !website.isEmpty {
                mapInfoRow(icon: "globe", text: website)
            }
            mapInfoRow(icon: "location.north.line", text: card.coordinateText)

            Text("点按查看详情 >")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.chatBoxSurfaceSolid)
    }

    private func mapRatingBadge(_ rating: Double) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "star.fill")
                .font(.system(size: 11))
            Text(String(format: "%.1f", rating))
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.14), in: Capsule())
    }

    private func mapInfoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .center)
                .padding(.top, 1)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
        }
    }
}

struct WeatherCardView: View {
    let card: WeatherCardPayload
    let detailText: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card.location).font(.system(size: 14, weight: .semibold))
                        Text(card.condition).font(.system(size: AppLayout.captionSize)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text("\(Int(card.currentTempC.rounded()))°")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.primary)
                }

                if !card.dailyForecasts.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(card.dailyForecasts.prefix(5)) { day in
                            VStack(spacing: 4) {
                                Text(day.day)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Image(systemName: weatherIcon(day.iconName))
                                    .font(.system(size: 13))
                                    .symbolRenderingMode(.multicolor)
                                Text("\(Int(day.highC))°")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .chatBoxGlassCard(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weatherIcon(_ name: String) -> String {
        switch name.lowercased() {
        case "sunny": return "sun.max.fill"
        case "partly_cloudy": return "cloud.sun.fill"
        case "cloudy": return "cloud.fill"
        case "rain": return "cloud.rain.fill"
        case "storm": return "cloud.bolt.rain.fill"
        case "snow": return "cloud.snow.fill"
        default: return "cloud.fill"
        }
    }
}

/// 简易流式布局
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
