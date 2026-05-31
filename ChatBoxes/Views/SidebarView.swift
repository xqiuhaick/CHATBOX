import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(ChatStore.self) private var store
    @Environment(\.openSettings) private var openSettings
    @Binding var searchText: String
    @Binding var composerText: String
    @Binding var renameSessionID: String
    @Binding var renameText: String
    @Binding var showRenameSheet: Bool

    private var filteredSessions: [ChatSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.sessions }
        return store.sessions.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("最近")
                    .font(.system(size: AppLayout.sidebarRecentHeaderSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppLayout.sidebarContentHorizontalInset)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                if filteredSessions.isEmpty {
                    Text(searchText.isEmpty ? "暂无对话" : "无匹配结果")
                        .font(.system(size: AppLayout.sidebarSessionTitleSize))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppLayout.sidebarContentHorizontalInset)
                        .padding(.top, 4)
                } else {
                    ForEach(filteredSessions) { session in
                        SidebarSessionRow(
                            title: session.title,
                            isSelected: store.activeSessionID == session.id
                        ) {
                            store.selectSession(session.id)
                        }
                        .contextMenu { sessionContextMenu(session) }
                    }
                }
            }
            .padding(.bottom, 56)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .bottom)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            userFooter
        }
    }

    @ViewBuilder
    private func sessionContextMenu(_ session: ChatSession) -> some View {
        Button("重命名") {
            renameSessionID = session.id
            renameText = session.title
            withAnimation(.chatBoxQuick) {
                showRenameSheet = true
            }
        }
        Button("复制对话") {
            copyToPasteboard(exportedConversationText(for: session))
        }
        Button("导出对话…") {
            exportSession(session)
        }
        Divider()
        Button("删除", role: .destructive) {
            store.deleteSession(session.id)
        }
        .disabled(store.sessions.count <= 1)
    }

    private var userFooter: some View {
        Button {
            openSettings()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 18, height: 18)

                Text("设置")
                    .font(.system(size: AppLayout.bodySize))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.sidebarContentHorizontalInset)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func exportSession(_ session: ChatSession) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(session.title).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? exportedConversationText(for: session).write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct SidebarSessionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: AppLayout.sidebarSessionTitleSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .padding(.horizontal, 10)
                .background {
                    if isSelected {
                        RoundedRectangle(
                            cornerRadius: AppLayout.sidebarSelectionCornerRadius,
                            style: .continuous
                        )
                        .fill(Color.chatBoxListSelection)
                    }
                }
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: AppLayout.sidebarSelectionCornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppLayout.sidebarContentHorizontalInset)
    }
}
