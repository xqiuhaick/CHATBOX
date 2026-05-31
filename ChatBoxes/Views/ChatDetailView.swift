import SwiftUI

struct ChatDetailView: View {
    @Environment(ChatStore.self) private var store
    @Binding var composerText: String
    @Binding var composerMode: ComposerMode
    @State private var isModelPickerPresented = false
    @State private var canvasPayload: CanvasPreviewPayload?

    var body: some View {
        HSplitView {
            chatColumn
                .layoutPriority(1)
            if let canvasPayload {
                CanvasSidePanelView(payload: canvasPayload, onClose: closeCanvas)
                    .frame(minWidth: 520, idealWidth: 720, maxWidth: 920)
                    .layoutPriority(0)
            }
        }
        .environment(\.openCanvasPreview, openCanvasPreview)
        .onChange(of: store.activeSessionID) { _, _ in
            canvasPayload = nil
        }
    }

    private func closeCanvas() {
        canvasPayload = nil
    }

    private func openCanvasPreview(_ payload: CanvasPreviewPayload) {
        if let current = canvasPayload, current.isSameArtifact(as: payload) {
            canvasPayload = nil
        } else {
            canvasPayload = payload
        }
    }

    private var chatColumn: some View {
        ZStack(alignment: .bottom) {
            Group {
                if store.activeSession?.messages.isEmpty ?? true {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    messageList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            composerDock
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.chatBoxCanvas)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ModelPickerMenu(isPresented: $isModelPickerPresented)
            }

            if let session = store.activeSession, !session.messages.isEmpty {
                let exportText = exportedConversationText(for: session)
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: exportText) {
                        Label("分享对话", systemImage: "square.and.arrow.up")
                    }
                    .help("分享对话")

                    Button {
                        copyToPasteboard(exportText)
                    } label: {
                        Label("复制对话", systemImage: "square.on.square")
                    }
                    .help("复制对话")
                }
            }
        }
    }

    private var composerDock: some View {
        ComposerView(
            text: $composerText,
            mode: $composerMode,
            isModelPickerPresented: $isModelPickerPresented
        )
        .chatBoxFloatingComposerLayout()
        .chatBoxComposerDock()
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: AppLayout.messageSpacing) {
                    if let session = store.activeSession {
                        ForEach(session.messages.filter { $0.role != .system }) { message in
                            MessageRowView(message: message) {
                                Task { await store.regenerateLastAssistant() }
                            }
                            .id(message.id)
                        }
                    }
                }
                .chatBoxCenteredContent()
                .padding(.top, 8)
                .padding(.bottom, AppLayout.composerDockReservedHeight)
            }
            .onChange(of: store.activeSession?.messages.count) { _, _ in
                scrollToLatestMessage(proxy, pinToBottom: isStreaming)
            }
            .onChange(of: store.activeSession?.messages.last?.content) { _, _ in
                scrollToLatestMessage(proxy, pinToBottom: isStreaming)
            }
            .onChange(of: isStreaming) { _, streaming in
                scrollToLatestMessage(proxy, pinToBottom: streaming)
            }
        }
    }

    private var isStreaming: Bool {
        store.activeSession?.messages.last?.generating == true
    }

    private func scrollToLatestMessage(_ proxy: ScrollViewProxy, pinToBottom: Bool) {
        guard let lastID = store.activeSession?.messages.last?.id else { return }
        let anchor: UnitPoint = pinToBottom ? .bottom : .top
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(lastID, anchor: anchor)
        }
    }
}
