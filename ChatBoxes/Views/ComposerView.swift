import AppKit
import AVFoundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

private enum ComposerVoicePhase: Equatable {
    case idle
    case listening
    case transcribing
}

enum ComposerMode: String, CaseIterable, Identifiable {
    case chat
    case webSearch
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "对话"
        case .webSearch: return "搜索"
        case .image: return "画图"
        }
    }

    var icon: String {
        switch self {
        case .chat: return "bubble.left"
        case .webSearch: return "globe"
        case .image: return "paintbrush"
        }
    }

    var placeholder: String {
        switch self {
        case .chat: return AppCopy.defaultComposerPlaceholder
        case .webSearch: return "搜索网页"
        case .image: return "描述你想画的图片"
        }
    }
}

struct ComposerView: View {
    @Environment(ChatStore.self) private var store
    @Binding var text: String
    @Binding var mode: ComposerMode
    @Binding var isModelPickerPresented: Bool

    @State private var isSending = false
    @State private var textAreaHeight: CGFloat = AppLayout.composerLineHeight
    @State private var attachedImageDataURL = ""
    @State private var attachedFileName = ""
    @State private var attachedFileExt = ""
    @State private var attachedFileText = ""
    @State private var showFileImporter = false
    @State private var voicePhase: ComposerVoicePhase = .idle
    @State private var voiceErrorMessage = ""
    @State private var showVoiceError = false

    private var speech: ChatBoxSpeechTranslationService { .shared }

    private var isGenerating: Bool {
        store.activeSession?.messages.contains(where: { $0.generating == true }) == true
    }

    private var clampedTextHeight: CGFloat {
        min(AppLayout.composerTextMaxHeight, max(AppLayout.composerLineHeight, textAreaHeight))
    }

    private var textInputHeight: CGFloat {
        max(
            AppLayout.composerLineHeight,
            activePanelHeight
                - attachmentBandHeight
                - AppLayout.composerToolbarHeight
                - AppLayout.composerInnerTopPadding
                - AppLayout.composerInnerBottomPadding
        )
    }

    private var panelHeight: CGFloat {
        let chrome = AppLayout.composerInnerTopPadding
            + AppLayout.composerInnerBottomPadding
            + AppLayout.composerToolbarHeight
        let content = attachmentBandHeight + clampedTextHeight + chrome
        return min(AppLayout.composerMaxHeight, max(AppLayout.composerMinHeight, content))
    }

    private var attachmentBandHeight: CGFloat {
        (!attachedImageDataURL.isEmpty || !attachedFileName.isEmpty) ? 36 : 0
    }

    private var activePanelHeight: CGFloat {
        voicePhase == .idle ? panelHeight : AppLayout.composerVoicePanelHeight
    }

    var body: some View {
        Group {
            if voicePhase == .idle {
                normalComposerBody
            } else {
                voiceInputPanel
            }
        }
        .frame(height: activePanelHeight)
        .chatBoxFloatingComposerChrome()
        .overlay {
            Button("", action: send)
                .keyboardShortcut(.return, modifiers: store.settings.sendWithCommandReturn ? .command : [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .plainText, .json, .data],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .onChange(of: store.draftToEdit) { _, newValue in
            guard !newValue.isEmpty else { return }
            text = newValue
            store.draftToEdit = ""
        }
        .animation(.chatBoxQuick, value: activePanelHeight)
        .animation(.chatBoxQuick, value: voicePhase)
        .alert("语音输入", isPresented: $showVoiceError) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(voiceErrorMessage)
        }
        .onDisappear {
            if voicePhase == .listening {
                speech.cancelRecording()
                voicePhase = .idle
            }
        }
    }

    private var normalComposerBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if attachmentBandHeight > 0 {
                attachmentChips
                    .padding(.horizontal, AppLayout.composerInnerHorizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
            }

            ComposerTextInput(
                text: $text,
                textHeight: $textAreaHeight,
                placeholder: composerPlaceholder,
                sendWithCommandReturn: store.settings.sendWithCommandReturn,
                onSend: send
            )
            .frame(height: textInputHeight)
            .padding(.horizontal, AppLayout.composerInnerHorizontalPadding)
            .padding(.top, AppLayout.composerInnerTopPadding)

            composerToolbar
                .frame(height: AppLayout.composerToolbarHeight)
                .padding(.horizontal, AppLayout.composerInnerHorizontalPadding - 2)
                .padding(.bottom, AppLayout.composerInnerBottomPadding)
        }
        .frame(height: activePanelHeight, alignment: .bottom)
    }

    private var voiceInputPanel: some View {
        HStack(spacing: 12) {
            Button {
                cancelVoiceInput()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.borderless)
            .help("取消")
            .disabled(voicePhase == .transcribing)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                if voicePhase == .listening {
                    VoiceInputWaveform()
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(voicePhase == .listening ? "正在倾听" : "正在转写…")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                Task { await finishVoiceInput() }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)
                    .background(Color.primary, in: Circle())
            }
            .buttonStyle(.borderless)
            .help("完成")
            .disabled(voicePhase == .transcribing)
        }
        .padding(.horizontal, AppLayout.composerInnerHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var composerToolbar: some View {
        HStack(alignment: .center, spacing: 6) {
            attachmentMenuButton
                .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)
            searchToggleButton
                .frame(height: AppLayout.composerToolSize)
            imageToggleButton
                .frame(height: AppLayout.composerToolSize)

            Spacer(minLength: 0)

            voiceButton
                .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)

            if isGenerating {
                stopButton
                    .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)
            } else {
                sendButton
                    .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var attachmentMenuButton: some View {
        Menu {
            Button("添加图片…") { pickImage() }
            Button("添加文件…") { showFileImporter = true }
        } label: {
            ComposerToolbarIcon(systemName: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("添加附件")
    }

    private var searchToggleButton: some View {
        ComposerSearchToggle(isOn: isSearchOn) {
            withAnimation(.chatBoxQuick) {
                mode = isSearchOn ? .chat : .webSearch
            }
        }
        .disabled(!store.settings.webSearchEnabled)
        .help(store.settings.webSearchEnabled ? (isSearchOn ? "关闭联网搜索" : "开启联网搜索") : "请先在设置中启用联网搜索")
    }

    private var imageToggleButton: some View {
        ComposerModeToggle(title: "画图", isOn: mode == .image) {
            withAnimation(.chatBoxQuick) {
                mode = mode == .image ? .chat : .image
            }
        } icon: {
            DrawIcon()
        }
        .help(mode == .image ? "关闭画图" : "画图")
    }

    private var voiceButton: some View {
        ComposerToolbarButton(action: {
            Task { await startVoiceInput() }
        }, help: "语音输入") {
            ComposerToolbarIcon(systemName: "mic")
        }
        .disabled(voicePhase != .idle || isGenerating)
    }

    private var stopButton: some View {
        ComposerToolbarButton(action: { store.stopGenerating() }, help: "停止生成") {
            Image(systemName: "stop.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: AppLayout.composerSendSize, height: AppLayout.composerSendSize)
                .background(Color.primary.opacity(0.78), in: Circle())
        }
    }

    private var sendButton: some View {
        ComposerToolbarButton(
            action: send,
            help: store.settings.sendWithCommandReturn ? "发送 (⌘↩)" : "发送 (↩)，换行 (⇧↩)"
        ) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(canSend ? Color.white : Color.secondary.opacity(0.7))
                .frame(width: AppLayout.composerSendSize, height: AppLayout.composerSendSize)
                .background(canSend ? Color.black : Color.primary.opacity(0.10), in: Circle())
        }
        .disabled(!canSend)
    }

    private var isSearchOn: Bool { mode == .webSearch }

    @ViewBuilder
    private var attachmentChips: some View {
        HStack(spacing: 6) {
            if !attachedImageDataURL.isEmpty {
                Label("图片", systemImage: "photo")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            if !attachedFileName.isEmpty {
                Label(attachedFileName, systemImage: "doc")
                    .font(.caption)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            Button { clearAttachments() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .foregroundStyle(.secondary)
    }

    private var composerPlaceholder: String {
        switch mode {
        case .chat: return AppCopy.composerPlaceholder(from: store.settings)
        case .webSearch: return mode.placeholder
        case .image: return mode.placeholder
        }
    }

    private var canSend: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .image {
            return !trimmed.isEmpty
        }
        return !trimmed.isEmpty || !attachedImageDataURL.isEmpty || !attachedFileName.isEmpty
    }

    private func send() {
        guard canSend, !isSending else { return }
        isSending = true
        let content = text
        let image = attachedImageDataURL
        let fileName = attachedFileName
        let fileExt = attachedFileExt
        let fileText = attachedFileText

        text = ""
        textAreaHeight = AppLayout.composerLineHeight
        clearAttachments()

        Task {
            if mode == .image {
                await store.generateImage(prompt: content)
            } else {
                await store.sendMessage(
                    content: content,
                    imageDataURL: image,
                    fileName: fileName,
                    fileExt: fileExt,
                    fileText: fileText,
                    useWebSearch: mode == .webSearch
                )
            }
            isSending = false
        }
    }

    private func clearAttachments() {
        attachedImageDataURL = ""
        attachedFileName = ""
        attachedFileExt = ""
        attachedFileText = ""
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        let mime: String
        switch ext {
        case "png": mime = "image/png"
        case "gif": mime = "image/gif"
        case "webp": mime = "image/webp"
        default: mime = "image/jpeg"
        }
        attachedImageDataURL = "data:\(mime);base64,\(data.base64EncodedString())"
    }

    private func isSTTConfigured() -> Bool {
        let settings = store.settings
        let provider = normalizeSpeechProviderID(settings.pluginSTTProvider)
        if provider == SpeechServiceProvider.system.rawValue {
            return true
        }
        if !normalizeAPIKey(settings.pluginSTTAPIKey).isEmpty {
            return true
        }
        if provider == SpeechServiceProvider.openai.rawValue {
            return !normalizeAPIKey(settings.openAIAPIKey).isEmpty
        }
        return false
    }

    private func startVoiceInput() async {
        guard voicePhase == .idle else { return }
        guard isSTTConfigured() else {
            voiceErrorMessage = "请先在设置 → 插件 → 语音转文本中配置 API Key。"
            showVoiceError = true
            return
        }

        if normalizeSpeechProviderID(store.settings.pluginSTTProvider) == SpeechServiceProvider.system.rawValue {
            let speechPermitted = await speech.requestSpeechRecognitionPermission()
            guard speechPermitted else {
                voiceErrorMessage = "需要语音识别权限。请在系统设置 → 隐私与安全性 → 语音识别中允许本应用。"
                showVoiceError = true
                return
            }
        }

        let permitted = await speech.requestMicrophonePermission()
        guard permitted else {
            voiceErrorMessage = "需要麦克风权限才能使用语音输入。请在系统设置中允许本应用访问麦克风。"
            showVoiceError = true
            return
        }

        do {
            try speech.startRecording()
            withAnimation(.chatBoxQuick) {
                voicePhase = .listening
            }
        } catch {
            voiceErrorMessage = error.localizedDescription
            showVoiceError = true
        }
    }

    private func cancelVoiceInput() {
        speech.cancelRecording()
        withAnimation(.chatBoxQuick) {
            voicePhase = .idle
        }
    }

    private func finishVoiceInput() async {
        guard voicePhase == .listening else { return }
        guard let capture = speech.stopRecording() else {
            cancelVoiceInput()
            return
        }

        withAnimation(.chatBoxQuick) {
            voicePhase = .transcribing
        }

        defer {
            try? FileManager.default.removeItem(at: capture.url)
        }

        do {
            let transcript = try await store.transcribeAudio(fileURL: capture.url)
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                voiceErrorMessage = "没有识别到可用文本，请重试。"
                showVoiceError = true
                voicePhase = .idle
                return
            }

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = trimmed
            } else {
                text += "\n" + trimmed
            }

            if store.settings.pluginSTTAddRecordingAsFile {
                attachedFileName = capture.url.lastPathComponent
                attachedFileExt = capture.url.pathExtension.lowercased()
                attachedFileText = trimmed
            }

            withAnimation(.chatBoxQuick) {
                voicePhase = .idle
            }
        } catch {
            voiceErrorMessage = error.localizedDescription
            showVoiceError = true
            voicePhase = .idle
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        attachedFileName = url.lastPathComponent
        attachedFileExt = url.pathExtension.lowercased()

        if attachedFileExt == "pdf", let doc = PDFDocument(url: url) {
            let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
            attachedFileText = String(text.prefix(12000))
        } else if let data = try? String(contentsOf: url, encoding: .utf8) {
            attachedFileText = String(data.prefix(12000))
        } else {
            attachedFileText = ""
        }
    }
}

// MARK: - Voice Input

private struct VoiceInputWaveform: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<5, id: \.self) { index in
                    let height = 5 + abs(sin(phase * 5 + Double(index) * 0.85)) * 11
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.secondary)
                        .frame(width: 3, height: height)
                }
            }
            .frame(height: 18)
        }
    }
}

// MARK: - Toolbar Controls

private struct ComposerSearchToggle: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        ComposerModeToggle(title: "搜索", isOn: isOn, action: action) {
            WebSearchGlobeIcon()
        }
    }
}

private struct ComposerModeToggle<Icon: View>: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var isHovered = false

    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon()
                    .frame(
                        width: AppLayout.composerToolbarIconContentSize - 1,
                        height: AppLayout.composerToolbarIconContentSize - 1
                    )
                if isOn {
                    Text(title)
                        .font(.system(size: AppLayout.composerToolbarFontSize, weight: .medium))
                }
            }
            .foregroundStyle(isOn ? Color.accentColor : Color.chatBoxComposerTool)
            .padding(.horizontal, isOn ? 10 : 0)
            .frame(
                width: isOn ? nil : AppLayout.composerToolSize,
                height: AppLayout.composerToolSize
            )
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                }
            }
            .animation(.chatBoxQuick, value: isOn)
        }
        .buttonStyle(.plain)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                isHovered = true
            case .ended:
                isHovered = false
            }
        }
        .background {
            if !isOn, isHovered {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
    }
}

private struct ComposerToolbarIcon: View {
    let systemName: String
    var isActive: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: AppLayout.composerToolbarIconContentSize - 1, weight: .medium))
            .foregroundStyle(isActive ? Color.chatBoxComposerToolActive : Color.chatBoxComposerTool)
            .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)
            .contentShape(Rectangle())
    }
}

private struct ComposerToolbarButton<Label: View>: View {
    let action: () -> Void
    let help: String
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(.plain)
            .help(help)
            .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovered = true
                case .ended:
                    isHovered = false
                }
            }
            .background {
                if isHovered {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: AppLayout.composerToolSize, height: AppLayout.composerToolSize)
                }
            }
    }
}

// MARK: - Text Input

private struct ComposerTextInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
    let placeholder: String
    let sendWithCommandReturn: Bool
    let onSend: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false

        let textView = ComposerNSTextView(frame: .zero)
        scrollView.documentView = textView
        context.coordinator.textView = textView
        textView.delegate = context.coordinator
        textView.onReturnKey = { [weak coordinator = context.coordinator] event in
            coordinator?.sendFromReturnKey(event) ?? false
        }
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = text
        context.coordinator.attach(to: textView)
        context.coordinator.updatePlaceholder()
        context.coordinator.updateHeight()

        return scrollView
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        context.coordinator.textView = textView
        textView.onReturnKey = { [weak coordinator = context.coordinator] event in
            coordinator?.sendFromReturnKey(event) ?? false
        }
        scrollView.hasVerticalScroller = context.coordinator.needsScroller
        context.coordinator.syncTextToViewIfNeeded(text)
        context.coordinator.updatePlaceholder()
        context.coordinator.updateHeight()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextInput
        weak var textView: NSTextView?
        private var placeholderLabel: NSTextField?
        private var textStorageObserver: NSObjectProtocol?
        var needsScroller = false
        private var skipNextBindingSync = false

        init(parent: ComposerTextInput) {
            self.parent = parent
        }

        func attach(to textView: NSTextView) {
            self.textView = textView
            guard textStorageObserver == nil else { return }
            textStorageObserver = NotificationCenter.default.addObserver(
                forName: NSText.didChangeNotification,
                object: textView.textStorage,
                queue: .main
            ) { [weak self] _ in
                self?.updatePlaceholder()
            }
        }

        func detach() {
            if let textStorageObserver {
                NotificationCenter.default.removeObserver(textStorageObserver)
                self.textStorageObserver = nil
            }
        }

        func updatePlaceholder() {
            guard let textView else { return }
            if placeholderLabel == nil {
                let label = NSTextField(labelWithString: parent.placeholder)
                label.font = .preferredFont(forTextStyle: .body)
                label.textColor = .secondaryLabelColor
                label.isBezeled = false
                label.isEditable = false
                label.isSelectable = false
                label.backgroundColor = .clear
                label.translatesAutoresizingMaskIntoConstraints = false
                textView.addSubview(label, positioned: .below, relativeTo: nil)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: textView.leadingAnchor),
                    label.topAnchor.constraint(equalTo: textView.topAnchor, constant: 2)
                ])
                placeholderLabel = label
            }
            placeholderLabel?.stringValue = parent.placeholder
            placeholderLabel?.isHidden = shouldHidePlaceholder(for: textView)
        }

        private func shouldHidePlaceholder(for textView: NSTextView) -> Bool {
            !textView.string.isEmpty || textView.hasMarkedText()
        }

        /// 仅在外部改 binding 时写回 NSTextView；IME 组合期间不能重置 string，否则预编辑会叠在已有文字上。
        func syncTextToViewIfNeeded(_ bindingText: String) {
            guard let textView else { return }
            if skipNextBindingSync {
                skipNextBindingSync = false
                return
            }
            guard !textView.hasMarkedText(), textView.string != bindingText else { return }
            textView.string = bindingText
        }

        func updateHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let used = layoutManager.usedRect(for: textContainer)
            let measured = max(
                AppLayout.composerLineHeight,
                ceil(used.height) + 4
            )
            let clamped = min(AppLayout.composerTextMaxHeight, measured)
            needsScroller = measured > AppLayout.composerTextMaxHeight

            if abs(parent.textHeight - clamped) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.textHeight = clamped
                }
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            skipNextBindingSync = true
            parent.text = textView.string
            updatePlaceholder()
            updateHeight()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            updatePlaceholder()
        }

        func sendFromReturnKey(_ event: NSEvent) -> Bool {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if parent.sendWithCommandReturn, !flags.contains(.command) {
                return false
            }
            parent.onSend()
            return true
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }

            let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
            if parent.sendWithCommandReturn {
                guard flags.contains(.command) else { return false }
                parent.onSend()
                return true
            }
            if flags.contains(.shift) { return false }
            parent.onSend()
            return true
        }
    }
}

private final class ComposerNSTextView: NSTextView {
    var onReturnKey: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        guard isReturnKey(event), !hasMarkedText() else {
            super.keyDown(with: event)
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) {
            super.keyDown(with: event)
            return
        }

        if onReturnKey?(event) == true {
            return
        }

        super.keyDown(with: event)
    }

    private func isReturnKey(_ event: NSEvent) -> Bool {
        event.keyCode == 36 || event.keyCode == 76
    }
}
