import SwiftUI

struct ContentView: View {
    @Environment(ChatStore.self) private var store
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var composerText = ""
    @State private var composerMode: ComposerMode = .chat
    @State private var renameSessionID = ""
    @State private var renameText = ""
    @State private var showRenameSheet = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            NavigationStack {
                SidebarView(
                    searchText: $searchText,
                    composerText: $composerText,
                    renameSessionID: $renameSessionID,
                    renameText: $renameText,
                    showRenameSheet: $showRenameSheet
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            store.createAndSelectSession()
                        } label: {
                            Label("新对话", systemImage: "square.and.pencil")
                        }
                        .help("新对话")
                    }
                }
            }
            .navigationSplitViewColumnWidth(
                min: AppLayout.sidebarMinWidth,
                ideal: AppLayout.sidebarIdealWidth,
                max: AppLayout.sidebarMaxWidth
            )
        } detail: {
            NavigationStack {
                ChatDetailView(
                    composerText: $composerText,
                    composerMode: $composerMode
                )
            }
        }
        .animation(.chatBoxSmooth, value: columnVisibility)
        .sheet(isPresented: $showRenameSheet) {
            RenameSessionSheet(
                title: $renameText,
                onCancel: {
                    withAnimation(.chatBoxQuick) {
                        showRenameSheet = false
                    }
                },
                onSave: {
                    store.renameSession(renameSessionID, title: renameText)
                    withAnimation(.chatBoxQuick) {
                        showRenameSheet = false
                    }
                }
            )
        }
        .onAppear {
            if store.settings.defaultWebSearchEnabled {
                composerMode = .webSearch
            }
        }
    }
}

struct RenameSessionSheet: View {
    @Binding var title: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("重命名对话")
                .font(.system(size: 14, weight: .semibold))

            TextField("标题", text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

#Preview {
    ContentView()
        .environment(ChatStore())
}
