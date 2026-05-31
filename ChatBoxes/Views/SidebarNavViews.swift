import SwiftUI

struct LibrarySidebarSection: View {
    @Environment(ChatStore.self) private var store
    @Binding var composerText: String

    @State private var newTitle = ""
    @State private var newContent = ""
    @State private var showAddSheet = false

    private var sidebarData: SidebarDataStore { SidebarDataStore.shared }

    var body: some View {
        Section {
            Button {
                if let session = store.activeSession {
                    sidebarData.addLibraryItem(
                        title: session.title,
                        content: exportedConversationText(for: session)
                    )
                } else {
                    showAddSheet = true
                }
            } label: {
                Label("保存当前对话", systemImage: "square.and.arrow.down")
                    .font(.system(size: AppLayout.bodySize))
            }
            .buttonStyle(.plain)

            Button { showAddSheet = true } label: {
                Label("新建条目", systemImage: "plus")
                    .font(.system(size: AppLayout.bodySize))
            }
            .buttonStyle(.plain)
        }

        Section("已保存") {
            if sidebarData.libraryItems.isEmpty {
                Text("暂无保存内容")
                    .font(.system(size: AppLayout.captionSize))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sidebarData.libraryItems) { item in
                    Button {
                        composerText = item.content
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: AppLayout.bodySize))
                                .lineLimit(1)
                            Text(item.content)
                                .font(.system(size: AppLayout.captionSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("复制") { copyToPasteboard(item.content) }
                        Button("删除", role: .destructive) { sidebarData.deleteLibraryItem(item.id) }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("新建库条目").font(.headline)
                TextField("标题", text: $newTitle)
                TextEditor(text: $newContent).frame(minHeight: 120)
                HStack {
                    Spacer()
                    Button("取消") { showAddSheet = false }
                    Button("保存") {
                        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let content = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty, !content.isEmpty else { return }
                        sidebarData.addLibraryItem(title: title, content: content)
                        newTitle = ""; newContent = ""; showAddSheet = false
                    }
                }
            }
            .padding(20)
            .frame(width: 420)
        }
    }
}
