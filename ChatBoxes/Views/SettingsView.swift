import SwiftUI

// MARK: - Settings Shell

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case providers
    case prompts
    case plugins
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .appearance: return "外观"
        case .providers: return "提供商"
        case .prompts: return "提示词"
        case .plugins: return "插件"
        case .advanced: return "高级"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .providers: return "cpu"
        case .prompts: return "book"
        case .plugins: return "puzzlepiece.extension"
        case .advanced: return "ellipsis.circle"
        }
    }

    var usesContentColumn: Bool {
        switch self {
        case .providers, .prompts, .plugins, .advanced: return true
        default: return false
        }
    }
}

enum AdvancedSettingsItem: String, CaseIterable, Identifiable {
    case about
    case network
    case privacy
    case data
    case markdown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .about: return "关于"
        case .network: return "联网搜索"
        case .privacy: return "隐私"
        case .data: return "数据"
        case .markdown: return "Markdown"
        }
    }
}

enum PluginSettingsItem: String, CaseIterable, Identifiable {
    case conversationTitle
    case textToSpeech
    case speechToText
    case vision
    case map
    case network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .conversationTitle: return "对话标题"
        case .textToSpeech: return "文本转语音"
        case .speechToText: return "语音转文本"
        case .vision: return "辅助视觉模型"
        case .map: return "地图"
        case .network: return "联网搜索"
        }
    }

    var icon: String {
        switch self {
        case .conversationTitle: return "text.bubble"
        case .textToSpeech: return "speaker.wave.2"
        case .speechToText: return "waveform.badge.mic"
        case .vision: return "eye"
        case .map: return "map"
        case .network: return "network"
        }
    }
}

struct SettingsView: View {
    @State private var infoMessage = ""
    @State private var showInfoAlert = false

    var body: some View {
        NavigationStack {
            SettingsHomePane()
                .navigationDestination(for: SettingsRoute.self) { route in
                    routeDestination(for: route)
                }
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 640)
        .alert("提示", isPresented: $showInfoAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(infoMessage)
        }
    }

    @ViewBuilder
    private func routeDestination(for route: SettingsRoute) -> some View {
        switch route {
        case .general:
            GeneralSettingsPane()
        case .appearance:
            AppearanceSettingsPane()
        case .providers:
            ProviderIndexPane()
        case .provider(let id):
            ProviderDetailPane(providerID: id)
        case .prompts:
            PromptIndexPane()
        case .prompt(let id):
            PromptDetailPane(presetID: id)
        case .plugins:
            PluginIndexPane()
        case .plugin(let item):
            pluginDetail(for: item)
        case .advanced:
            AdvancedIndexPane()
        case .advancedItem(let item):
            advancedDetail(for: item)
        }
    }

    @ViewBuilder
    private func pluginDetail(for plugin: PluginSettingsItem) -> some View {
        switch plugin {
        case .conversationTitle:
            ConversationTitlePluginPane()
        case .textToSpeech:
            TextToSpeechPluginPane()
        case .speechToText:
            SpeechToTextPluginPane()
        case .vision:
            VisionHelperPluginPane()
        case .map:
            MapPluginPane()
        case .network:
            NetworkSettingsPane()
        }
    }

    @ViewBuilder
    private func advancedDetail(for item: AdvancedSettingsItem) -> some View {
        switch item {
        case .about:
            AdvancedAboutPane(showInfo: showInfo)
        case .network:
            AdvancedNetworkPane()
        case .privacy:
            AdvancedPrivacyPane()
        case .data:
            AdvancedDataPane(showInfo: showInfo)
        case .markdown:
            MarkdownSettingsPane()
        }
    }

    private func showInfo(_ message: String) {
        infoMessage = message
        showInfoAlert = true
    }
}

enum SettingsRoute: Hashable {
    case general
    case appearance
    case providers
    case provider(String)
    case prompts
    case prompt(String)
    case plugins
    case plugin(PluginSettingsItem)
    case advanced
    case advancedItem(AdvancedSettingsItem)
}

// MARK: - Shared Layout

enum SettingsMetrics {
    static let toolbarTitleSize: CGFloat = 13
    static let rowTitleSize: CGFloat = 13
    static let rowValueSize: CGFloat = 12
    static let rowIconSize: CGFloat = 14
    static let fieldLabelSize: CGFloat = 13
    static let fieldValueSize: CGFloat = 13
    static let detailHorizontalPadding: CGFloat = 20
    static let detailVerticalPadding: CGFloat = 16
    static let controlHeight: CGFloat = 28
    static let smallCaptionSize: CGFloat = 9
    static let backChevronSize: CGFloat = 12
    static let emptyStateIconSize: CGFloat = 20
    static let aboutAppIconSize: CGFloat = 24
}

struct SettingsHomePane: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        SettingsGroupedForm {
            Section("常规") {
                SettingsNavRow(title: "通用", icon: "gearshape", route: .general)
                SettingsNavRow(title: "外观", icon: "paintpalette", route: .appearance)

                Toggle(isOn: defaultSearchBinding) {
                    Label("默认开启联网搜索", systemImage: "globe")
                }
            }

            Section("应用") {
                SettingsNavRow(
                    title: "提供商",
                    value: providerTitle(for: store.settings.provider),
                    icon: "server.rack",
                    route: .providers
                )
                SettingsNavRow(title: "提示词", icon: "text.badge.star", route: .prompts)
                SettingsNavRow(title: "插件", icon: "puzzlepiece.extension", route: .plugins)
                SettingsNavRow(title: "高级", icon: "slider.horizontal.3", route: .advanced)
            }
        }
        .navigationTitle("设置")
        .toolbarTitleDisplayMode(.inline)
    }

    private var defaultSearchBinding: Binding<Bool> {
        Binding(
            get: { store.settings.defaultWebSearchEnabled },
            set: { value in var next = store.settings; next.defaultWebSearchEnabled = value; store.updateSettings(next) }
        )
    }
}

struct ProviderIndexPane: View {
    @Environment(ChatStore.self) private var store

    private var providers: [ProviderMeta] {
        providerList.sorted { lhs, rhs in
            if lhs.id == "custom" { return false }
            if rhs.id == "custom" { return true }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    var body: some View {
        SettingsGroupedForm {
            Section {
                ForEach(providers) { provider in
                    SettingsNavRow(
                        title: provider.title,
                        value: configuredValue(for: provider),
                        icon: "server.rack",
                        route: .provider(provider.id)
                    )
                }
            }
        }
        .settingsPageTitle("提供商")
    }

    private func configuredValue(for provider: ProviderMeta) -> String {
        let keys = providerMap(from: store.settings.providerAPIKeysJSON)
        if store.settings.provider == provider.id {
            return "当前"
        }
        return (keys[provider.id]?.isEmpty == false) ? "已配置" : ""
    }
}

struct PromptIndexPane: View {
    private var presets: [CustomGPTPreset] { SidebarDataStore.shared.gptPresets }

    var body: some View {
        SettingsGroupedForm {
            Section {
                ForEach(presets) { preset in
                    SettingsNavRow(
                        title: preset.name,
                        value: providerTitle(for: preset.provider),
                        icon: preset.icon,
                        route: .prompt(preset.id)
                    )
                }
            }
        }
        .settingsPageTitle("提示词")
    }
}

struct PluginIndexPane: View {
    var body: some View {
        SettingsGroupedForm {
            Section {
                ForEach(PluginSettingsItem.allCases) { item in
                    SettingsNavRow(
                        title: item.title,
                        icon: item.icon,
                        route: .plugin(item)
                    )
                }
            }
        }
        .settingsPageTitle("插件")
    }
}

struct AdvancedIndexPane: View {
    var body: some View {
        SettingsGroupedForm {
            Section {
                ForEach(AdvancedSettingsItem.allCases) { item in
                    SettingsNavRow(
                        title: item.title,
                        icon: icon(for: item),
                        route: .advancedItem(item)
                    )
                }
            }
        }
        .settingsPageTitle("高级")
    }

    private func icon(for item: AdvancedSettingsItem) -> String {
        switch item {
        case .about: return "info.circle"
        case .network: return "network"
        case .privacy: return "hand.raised"
        case .data: return "externaldrive"
        case .markdown: return "text.alignleft"
        }
    }
}

struct SettingsGroupedForm<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .environment(\.font, .system(size: SettingsMetrics.rowTitleSize))
    }
}

private struct SettingsSubpageToolbarModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    let title: String

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarBackButtonHidden(true)
            .toolbarVisibility(.hidden, for: .windowToolbar)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(alignment: .center, spacing: 10) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: SettingsMetrics.backChevronSize, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color(nsColor: .controlBackgroundColor), in: Circle())
                            .shadow(color: .black.opacity(0.08), radius: 5, y: 2)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("返回")

                    Text(title)
                        .font(.system(size: SettingsMetrics.toolbarTitleSize, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }
    }
}

extension View {
    func settingsPageTitle(_ title: String) -> some View {
        modifier(SettingsSubpageToolbarModifier(title: title))
    }
}

struct SettingsNavRow: View {
    let title: String
    var value: String = ""
    let icon: String
    let route: SettingsRoute
    var titleSize: CGFloat = SettingsMetrics.rowTitleSize
    var valueSize: CGFloat = SettingsMetrics.rowValueSize

    var body: some View {
        NavigationLink(value: route) {
            if value.isEmpty {
                Label(title, systemImage: icon)
                    .font(.system(size: titleSize))
            } else {
                LabeledContent {
                    Text(value)
                        .font(.system(size: valueSize))
                        .foregroundStyle(.secondary)
                } label: {
                    Label(title, systemImage: icon)
                        .font(.system(size: titleSize))
                }
            }
        }
    }
}

struct SettingsFooterText: View {
    let message: String
    let linkTitle: String
    let linkURL: URL

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(message + " ")
            Link(linkTitle, destination: linkURL)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct SettingsSectionGlassPicker: View {
    @Binding var selection: SettingsSection

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SettingsSection.allCases) { section in
                Button {
                    selection = section
                } label: {
                    Image(systemName: section.icon)
                        .font(.system(size: SettingsMetrics.rowIconSize, weight: .medium))
                        .foregroundStyle(selection == section ? .primary : .secondary)
                        .frame(width: 42, height: 42)
                        .background {
                            if selection == section {
                                Circle()
                                    .fill(Color.primary.opacity(0.12))
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(section.title)

                if section != SettingsSection.allCases.last {
                    Divider()
                        .frame(height: 22)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .chatBoxLiquidGlass(cornerRadius: 30, interactive: true)
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
}

struct SettingsGlassSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: SettingsMetrics.rowIconSize, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: SettingsMetrics.fieldValueSize, weight: .medium))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .chatBoxLiquidGlass(cornerRadius: 32, interactive: true)
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

struct SettingsSectionList: View {
    @Binding var selection: SettingsSection

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        SettingsSidebarRow(
                            icon: section.icon,
                            title: section.title,
                            tint: .primary,
                            isSelected: selection == section
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
    }
}

struct SettingsSidebarRow: View {
    let icon: String
    let title: String
    let tint: Color
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: SettingsMetrics.rowIconSize, weight: .semibold))
                        .foregroundStyle(.primary)
                }

            Text(title)
                .font(.system(size: SettingsMetrics.rowTitleSize, weight: .regular))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.12))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SettingsDetailScaffold<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Spacer(minLength: 0)
                    trailing()
                }
                .frame(maxWidth: .infinity)

                content()
            }
            .padding(.horizontal, SettingsMetrics.detailHorizontalPadding)
            .padding(.bottom, SettingsMetrics.detailVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .settingsPageTitle(title)
    }
}

struct SettingsEmptyDetail: View {
    var icon: String = "sidebar.left"
    var title: String = "设置"
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: SettingsMetrics.emptyStateIconSize))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct SettingsFieldGroup<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: SettingsMetrics.fieldLabelSize, weight: .semibold))
            content()
        }
    }
}

struct SettingsSecureField: View {
    let label: String
    @Binding var text: String
    @State private var isVisible = false

    var body: some View {
        SettingsFieldGroup(label: label) {
            HStack(spacing: 8) {
                Group {
                    if isVisible {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: SettingsMetrics.fieldValueSize))
                .padding(.horizontal, 14)
                .frame(height: SettingsMetrics.controlHeight)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye" : "eye.slash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(isVisible ? "隐藏" : "显示")
            }
        }
    }
}

struct ProviderIconView: View {
    let provider: ProviderMeta

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 34, height: 34)
            Text(provider.icon)
                .font(.system(size: SettingsMetrics.rowTitleSize, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Content Lists

struct ProviderSettingsList: View {
    @Binding var selection: String?
    @Binding var searchText: String

    private var providers: [ProviderMeta] {
        let sorted = providerList.sorted { lhs, rhs in
            if lhs.id == "custom" { return false }
            if rhs.id == "custom" { return true }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(providers) { provider in
                    Button {
                        selection = provider.id
                    } label: {
                        HStack(spacing: 14) {
                            ProviderIconView(provider: provider)
                            Text(provider.title)
                                .font(.system(size: SettingsMetrics.rowTitleSize))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .background {
                            if selection == provider.id {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.12))
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
    }
}

struct PluginSettingsList: View {
    @Binding var selection: PluginSettingsItem?
    @Binding var searchText: String

    private var items: [PluginSettingsItem] {
        guard !searchText.isEmpty else { return PluginSettingsItem.allCases }
        return PluginSettingsItem.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(items) { item in
                    Button {
                        selection = item
                    } label: {
                        SettingsSidebarRow(
                            icon: item.icon,
                            title: item.title,
                            tint: .primary,
                            isSelected: selection == item
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
    }
}

struct PromptSettingsList: View {
    @Binding var selection: String?
    @Binding var searchText: String

    private var sidebarData: SidebarDataStore { SidebarDataStore.shared }

    private var presets: [CustomGPTPreset] {
        guard !searchText.isEmpty else { return sidebarData.gptPresets }
        return sidebarData.gptPresets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.instructions.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(presets) { preset in
                    Button {
                        selection = preset.id
                    } label: {
                        SettingsSidebarRow(
                            icon: preset.icon,
                            title: preset.name,
                            tint: .primary,
                            isSelected: selection == preset.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - General & Advanced

struct GeneralSettingsPane: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        SettingsGroupedForm {
            Section("输入") {
                TextField("自定义输入提示（留空为默认）", text: placeholderBinding)
                Toggle("⌘ + Enter 发送", isOn: commandReturnBinding)
                Toggle("默认开启联网搜索", isOn: defaultSearchBinding)
            }

            Section("消息") {
                Toggle("显示消息时间戳", isOn: timestampBinding)
            }

            Section("模型") {
                favoriteModelsSection
            }

            Section("数据") {
                LabeledContent("会话数量", value: "\(store.sessions.count)")
            }
        }
        .settingsPageTitle("通用")
    }

    private var placeholderBinding: Binding<String> {
        Binding(
            get: { store.settings.customComposerPlaceholder },
            set: { v in var n = store.settings; n.customComposerPlaceholder = v; store.updateSettings(n) }
        )
    }

    private var commandReturnBinding: Binding<Bool> {
        Binding(
            get: { store.settings.sendWithCommandReturn },
            set: { v in var n = store.settings; n.sendWithCommandReturn = v; store.updateSettings(n) }
        )
    }

    private var defaultSearchBinding: Binding<Bool> {
        Binding(
            get: { store.settings.defaultWebSearchEnabled },
            set: { v in var n = store.settings; n.defaultWebSearchEnabled = v; store.updateSettings(n) }
        )
    }

    private var timestampBinding: Binding<Bool> {
        Binding(
            get: { store.settings.showMessageTimestamps },
            set: { v in var n = store.settings; n.showMessageTimestamps = v; store.updateSettings(n) }
        )
    }

    @ViewBuilder
    private var favoriteModelsSection: some View {
        let favorites = store.allFavoriteModels()
        if favorites.isEmpty {
            Text("在「提供商」详情页点击星标即可收藏模型。")
                .font(.system(size: SettingsMetrics.smallCaptionSize))
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(favorites.enumerated()), id: \.offset) { _, item in
                Button {
                    store.applyModel(provider: item.0.id, model: item.1)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.1).font(.system(size: SettingsMetrics.fieldValueSize))
                            Text(item.0.title).font(.system(size: SettingsMetrics.smallCaptionSize)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.settings.model == item.1 && store.settings.provider == item.0.id {
                            Image(systemName: "checkmark").foregroundStyle(.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct AdvancedSettingsList: View {
    @Binding var selection: AdvancedSettingsItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(AdvancedSettingsItem.allCases) { item in
                    Button {
                        selection = item
                    } label: {
                        SettingsSidebarRow(
                            icon: icon(for: item),
                            title: item.title,
                            tint: .primary,
                            isSelected: selection == item
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 18)
        }
        .scrollIndicators(.hidden)
    }

    private func icon(for item: AdvancedSettingsItem) -> String {
        switch item {
        case .about: return "info.circle"
        case .network: return "network"
        case .privacy: return "hand.raised"
        case .data: return "externaldrive"
        case .markdown: return "text.alignleft"
        }
    }
}

struct MarkdownSettingsPane: View {
    var body: some View {
        SettingsGroupedForm {
            Section {
                MarkdownMessageView(
                    text: MarkdownSettingsPane.previewMarkdown,
                    isGenerating: false,
                    searchResults: MarkdownSettingsPane.previewSearchResults
                )
                .padding(.vertical, 6)
            } header: {
                Text("预览")
            } footer: {
                Text("支持 Markdown、代码高亮、LaTeX（$行内$ / $$块$$）、Mermaid（预览 + 源码）、表格横向滚动、嵌套列表、图片、删除线、引用芯片 [1]、任务列表、Canvas 预览与 HTML 行内/代码块。")
                    .font(.system(size: SettingsMetrics.smallCaptionSize))
            }
        }
        .settingsPageTitle("Markdown")
    }

    static let previewMarkdown = """
    ## Markdown 预览

    行内公式 $E=mc^2$，以及 **粗体**、*斜体*、~~删除线~~、`代码`、[链接](https://example.com) 与引用 [1]。

    - 一级列表
      - 嵌套子项
      - 另一个子项
    1. 有序项
      1. 嵌套有序

    - [x] 已完成任务
    - [ ] 待办任务

    | 功能 | 状态 |
    | --- | --- |
    | Table | ✅ |
    | NestedList | ✅ |

    $$\\int_0^1 x^2 dx = \\frac{1}{3}$$

    > 引用与 <mark>HTML 行内高亮</mark> 标签

    ```svg
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 80">
      <ellipse cx="60" cy="70" rx="36" ry="8" fill="#ddd"/>
      <circle cx="60" cy="38" r="22" fill="#f4c2a1"/>
      <ellipse cx="38" cy="30" rx="8" ry="16" fill="#ddd"/>
      <ellipse cx="82" cy="30" rx="8" ry="16" fill="#ddd"/>
    </svg>
    ```

    ![示例图片](https://picsum.photos/seed/chatboxes/480/240)

    ```mermaid
    graph LR
      A[Markdown] --> B[ChatBoxes]
    ```
    """

    static let previewSearchResults: [WebSearchResultItem] = [
        WebSearchResultItem(title: "示例来源", snippet: "Markdown 预览用引用", url: "https://example.com")
    ]
}

struct AdvancedAboutPane: View {
    let showInfo: (String) -> Void

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        let date = formatter.string(from: Date())
        return "ChatBoxes v\(version) (\(build)) (\(date))"
    }

    var body: some View {
        SettingsGroupedForm {
            Section {
                VStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 58, height: 58)
                        .overlay {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: SettingsMetrics.aboutAppIconSize))
                                .foregroundStyle(.primary)
                        }

                    Text(appVersionText)
                        .font(.system(size: SettingsMetrics.rowTitleSize, weight: .semibold))

                    Button("复制调试信息") {
                        copyToPasteboard(debugInfoText())
                        showInfo("已复制调试信息。")
                    }
                    .font(.system(size: SettingsMetrics.rowTitleSize))
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
        }
        .settingsPageTitle("关于")
    }

    private func debugInfoText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "ChatBoxes \(version) (\(build))\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    }
}

struct AdvancedNetworkPane: View {
    var body: some View {
        NetworkSettingsPane()
    }
}

struct AdvancedPrivacyPane: View {
    var body: some View {
        SettingsGroupedForm {
            Section("数据存储") {
                LabeledContent("存储位置", value: "本机")
                Text("API 密钥与对话数据仅保存在本机，不会上传到云端。")
                    .font(.system(size: SettingsMetrics.smallCaptionSize))
                    .foregroundStyle(.secondary)
            }

            Section("系统权限") {
                LabeledContent("网络", value: "调用模型与搜索时需要")
                LabeledContent("麦克风", value: "使用语音输入时申请")
                LabeledContent("文件", value: "导入附件时由你选择")
            }
        }
        .settingsPageTitle("隐私")
    }
}

struct AdvancedDataPane: View {
    @Environment(ChatStore.self) private var store
    let showInfo: (String) -> Void

    var body: some View {
        SettingsGroupedForm {
            Section("存储") {
                LabeledContent("会话数量", value: "\(store.sessions.count)")
                Button("清除已保存的 API 密钥") {
                    store.clearStoredAPISecrets()
                    showInfo("已清除保存的 API 密钥。")
                }
            }
        }
        .settingsPageTitle("数据")
    }
}

struct AdvancedPlaceholderPane: View {
    let title: String
    let message: String

    var body: some View {
        SettingsEmptyDetail(title: title, message: message)
    }
}

struct AppearanceSettingsPane: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        SettingsGroupedForm {
            Section {
                Picker("显示模式", selection: appearanceBinding) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("材质强度", selection: glassBinding) {
                    ForEach(AppGlassIntensity.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
        }
        .settingsPageTitle("外观")
    }

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { store.settings.appearanceMode },
            set: { v in var n = store.settings; n.appearanceMode = v; store.updateSettings(n) }
        )
    }

    private var glassBinding: Binding<AppGlassIntensity> {
        Binding(
            get: { store.settings.glassIntensity },
            set: { v in var n = store.settings; n.glassIntensity = v; store.updateSettings(n) }
        )
    }
}

// MARK: - Provider Detail

struct ProviderDetailPane: View {
    @Environment(ChatStore.self) private var store
    let providerID: String

    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var useDefaultBaseURL = true
    @State private var models: [String] = []
    @State private var fetchedModels: [String] = []
    @State private var selectedModel = ""
    @State private var fetchError = ""
    @State private var isFetching = false

    var body: some View {
        SettingsDetailScaffold(title: providerTitle(for: providerID)) {
            configurationBadge
        } content: {
            VStack(alignment: .leading, spacing: 26) {
                SettingsSecureField(label: "API 密钥", text: $apiKey)

                if supportsDefaultBaseURL {
                    Toggle("使用默认 URL", isOn: $useDefaultBaseURL)
                    if useDefaultBaseURL {
                        SettingsFieldGroup(label: "API 地址") {
                            Text(defaultBaseURL(for: providerID))
                                .font(.system(size: SettingsMetrics.fieldValueSize))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .frame(height: SettingsMetrics.controlHeight)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }

                if !supportsDefaultBaseURL || !useDefaultBaseURL {
                    SettingsFieldGroup(label: "API 地址") {
                        TextField("", text: $baseURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: SettingsMetrics.fieldValueSize))
                            .padding(.horizontal, 14)
                            .frame(height: SettingsMetrics.controlHeight)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            }
                    }
                }

                Divider()

                HStack {
                    Button(isFetching ? "获取中…" : "获取模型列表") { Task { await fetchModels() } }
                        .controlSize(.large)
                        .disabled(isFetching || resolvedBaseURL.isEmpty)
                    Spacer()
                }

                if !models.isEmpty {
                    SettingsFieldGroup(label: "模型") {
                        VStack(spacing: 0) {
                            ForEach(models, id: \.self) { model in
                                modelRow(model)
                                if model != models.last {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                if !fetchedModels.isEmpty {
                    SettingsFieldGroup(label: "获取到的模型") {
                        VStack(spacing: 0) {
                            ForEach(fetchedModels, id: \.self) { model in
                                Button {
                                    if !models.contains(model) { models.append(model) }
                                    selectedModel = model
                                    persist()
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(model)
                                                .font(.system(size: SettingsMetrics.fieldValueSize))
                                            Text(models.contains(model) ? "已加入" : "点按添加")
                                                .font(.system(size: SettingsMetrics.smallCaptionSize))
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                                if model != fetchedModels.last {
                                    Divider()
                                }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                if !fetchError.isEmpty {
                    Text(fetchError)
                        .font(.system(size: SettingsMetrics.smallCaptionSize))
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear { loadFromStore() }
        .onChange(of: providerID) { _, _ in loadFromStore() }
        .onChange(of: apiKey) { _, _ in persist() }
        .onChange(of: baseURL) { _, _ in persist() }
        .onChange(of: useDefaultBaseURL) { _, _ in persist() }
        .onChange(of: selectedModel) { _, model in
            if !model.isEmpty { store.applyModel(provider: providerID, model: model) }
        }
    }

    @ViewBuilder
    private var configurationBadge: some View {
                let configured = !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        HStack(spacing: 4) {
            Image(systemName: configured ? "checkmark.circle.fill" : "circle.dotted")
            Text(configured ? "已配置" : "未配置")
        }
        .font(.system(size: SettingsMetrics.fieldValueSize, weight: .medium))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func modelRow(_ model: String) -> some View {
        HStack {
            Button { selectedModel = model } label: {
                HStack {
                    Text(model).font(.system(size: SettingsMetrics.fieldValueSize, weight: .regular))
                    Spacer()
                    if selectedModel == model {
                        Image(systemName: "checkmark")
                            .font(.system(size: SettingsMetrics.rowIconSize, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    if store.favoriteModels(for: providerID).contains(model) {
                        Image(systemName: "star.fill")
                            .font(.system(size: SettingsMetrics.rowIconSize))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            Button { store.toggleFavorite(model: model, provider: providerID) } label: {
                Image(systemName: store.favoriteModels(for: providerID).contains(model) ? "star.fill" : "star")
                    .font(.system(size: SettingsMetrics.rowIconSize))
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 6)
        }
    }

    private var supportsDefaultBaseURL: Bool {
        !defaultBaseURL(for: providerID).isEmpty
    }

    private var resolvedBaseURL: String {
        if supportsDefaultBaseURL && useDefaultBaseURL { return defaultBaseURL(for: providerID) }
        return baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadFromStore() {
        let keys = providerMap(from: store.settings.providerAPIKeysJSON)
        let urls = providerMap(from: store.settings.providerBaseURLsJSON)
        let modelMap = providerMap(from: store.settings.providerModelsJSON)
        apiKey = keys[providerID] ?? ""
        baseURL = urls[providerID] ?? defaultBaseURL(for: providerID)
        useDefaultBaseURL = supportsDefaultBaseURL && (urls[providerID]?.isEmpty ?? true)
        models = csvItems(modelMap[providerID] ?? defaultModelsCSV(for: providerID))
        selectedModel = store.settings.provider == providerID ? store.settings.model : models.first ?? ""
        fetchedModels = []
        fetchError = ""
    }

    private func persist() {
        var keys = providerMap(from: store.settings.providerAPIKeysJSON)
        var urls = providerMap(from: store.settings.providerBaseURLsJSON)
        var modelMap = providerMap(from: store.settings.providerModelsJSON)
        keys[providerID] = normalizeAPIKey(apiKey)
        urls[providerID] = useDefaultBaseURL && supportsDefaultBaseURL ? "" : baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        modelMap[providerID] = models.joined(separator: ",")
        var next = store.settings
        next.providerAPIKeysJSON = jsonString(from: keys)
        next.providerBaseURLsJSON = jsonString(from: urls)
        next.providerModelsJSON = jsonString(from: modelMap)
        if store.settings.provider == providerID {
            next.apiKey = keys[providerID] ?? ""
            next.baseURL = resolvedBaseURL
            if !selectedModel.isEmpty { next.model = selectedModel }
        }
        store.updateSettings(next)
    }

    private func fetchModels() async {
        isFetching = true
        fetchError = ""
        defer { isFetching = false }
        do {
            fetchedModels = try await ChatAPIService.shared.fetchModels(baseURL: resolvedBaseURL, apiKey: apiKey)
            store.appendModels(fetchedModels, for: providerID)
            loadFromStore()
        } catch {
            fetchError = error.localizedDescription
        }
    }
}

// MARK: - Prompt Detail

struct PromptDetailPane: View {
    let presetID: String

    private var sidebarData: SidebarDataStore { SidebarDataStore.shared }

    private var preset: CustomGPTPreset? {
        sidebarData.gptPresets.first { $0.id == presetID }
    }

    var body: some View {
        if let preset {
            SettingsDetailScaffold(title: preset.name) {
                HStack(spacing: 4) {
                    Image(systemName: preset.icon)
                    Text(preset.model)
                }
                .font(.system(size: SettingsMetrics.smallCaptionSize))
                .foregroundStyle(.secondary)
            } content: {
                VStack(alignment: .leading, spacing: 20) {
                    SettingsFieldGroup(label: "提供商") {
                        Text(providerTitle(for: preset.provider))
                            .foregroundStyle(.secondary)
                    }
                    SettingsFieldGroup(label: "模型") {
                        Text(preset.model)
                            .foregroundStyle(.secondary)
                    }
                    SettingsFieldGroup(label: "系统提示词") {
                        Text(preset.instructions)
                            .font(.system(size: SettingsMetrics.fieldValueSize))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Button("复制提示词") {
                        copyToPasteboard(preset.instructions)
                    }
                }
            }
        } else {
            SettingsEmptyDetail(message: "未找到该预设")
        }
    }
}

// MARK: - Plugin Panes

struct ConversationTitlePluginPane: View {
    @Environment(ChatStore.self) private var store

    private var configuredProviders: [ProviderMeta] {
        store.configuredProviders()
    }

    private var titleModels: [String] {
        models(for: store.settings.pluginTitleProvider)
    }

    var body: some View {
        SettingsGroupedForm {
            if configuredProviders.isEmpty {
                Section {
                    Text("请先在「提供商」中配置 API Key，才能使用 AI 生成对话标题。")
                        .font(.system(size: SettingsMetrics.smallCaptionSize))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("标题生成模型") {
                    Picker("提供商", selection: titleProviderBinding) {
                        ForEach(configuredProviders) { p in
                            Text(p.title).tag(p.id)
                        }
                    }
                    Picker("模型", selection: titleModelBinding) {
                        ForEach(titleModels, id: \.self) { model in
                            Text(modelShortName(model)).tag(model)
                        }
                    }
                }
            }
            Section("自动更新") {
                Picker("更新时机", selection: titleModeBinding) {
                    ForEach(ConversationTitleUpdateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
        }
        .settingsPageTitle("对话标题")
        .onAppear(perform: syncTitlePluginSelection)
    }

    private var titleProviderBinding: Binding<String> {
        Binding(get: { store.settings.pluginTitleProvider }, set: { value in
            var next = store.settings
            next.pluginTitleProvider = value
            let available = models(for: value)
            if !available.contains(next.pluginTitleModel) {
                next.pluginTitleModel = available.first ?? csvItems(defaultModelsCSV(for: value)).first ?? next.pluginTitleModel
            }
            store.updateSettings(next)
        })
    }

    private var titleModelBinding: Binding<String> {
        Binding(get: { store.settings.pluginTitleModel }, set: { value in
            var next = store.settings
            next.pluginTitleModel = value
            store.updateSettings(next)
        })
    }

    private var titleModeBinding: Binding<ConversationTitleUpdateMode> {
        Binding(get: { store.settings.pluginTitleUpdateMode }, set: { value in
            var next = store.settings
            next.pluginTitleUpdateMode = value
            store.updateSettings(next)
        })
    }

    private func models(for provider: String) -> [String] {
        csvItems(providerMap(from: store.settings.providerModelsJSON)[provider] ?? defaultModelsCSV(for: provider))
    }

    private func syncTitlePluginSelection() {
        guard !configuredProviders.isEmpty else { return }
        var next = store.settings
        if !configuredProviders.contains(where: { $0.id == next.pluginTitleProvider }) {
            next.pluginTitleProvider = configuredProviders[0].id
        }
        let available = models(for: next.pluginTitleProvider)
        if !available.contains(next.pluginTitleModel) {
            next.pluginTitleModel = available.first ?? next.pluginTitleModel
        }
        if next != store.settings {
            store.updateSettings(next)
        }
    }
}

struct TextToSpeechPluginPane: View {
    @Environment(ChatStore.self) private var store
    @State private var apiKey = ""
    @State private var baseURL = ""
    @State private var prompt = ""

    private var selectedProvider: String {
        store.settings.pluginTTSProvider
    }

    private var requiresAPIKey: Bool {
        speechProviderRequiresAPIKey(selectedProvider)
    }

    var body: some View {
        SettingsGroupedForm {
            Section("连接") {
                Picker("提供商", selection: ttsProviderBinding) {
                    ForEach(SpeechServiceProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                if requiresAPIKey {
                    SecureField("API 密钥", text: $apiKey)
                    TextField("API 地址", text: $baseURL)
                } else {
                    Text("使用 macOS 内置语音合成，无需 API Key。")
                        .font(.system(size: SettingsMetrics.smallCaptionSize))
                        .foregroundStyle(.secondary)
                }
            }
            Section("模型与声音") {
                Picker("模型", selection: ttsModelBinding) {
                    ForEach(speechTTSPModels(for: selectedProvider), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                Picker("声音", selection: ttsVoiceBinding) {
                    ForEach(speechTTSVoiceOptions(for: selectedProvider)) { voice in
                        Text(voice.title).tag(voice.id)
                    }
                }
            }
            if normalizeSpeechProviderID(selectedProvider) == SpeechServiceProvider.openai.rawValue {
                Section("提示词") {
                    TextEditor(text: $prompt).frame(minHeight: 100)
                }
            }
        }
        .settingsPageTitle("文本转语音")
        .onAppear(perform: loadFromStore)
        .onChange(of: apiKey) { _, value in
            var next = store.settings
            next.pluginTTSAPIKey = normalizeAPIKey(value)
            store.updateSettings(next)
        }
        .onChange(of: baseURL) { _, value in
            var next = store.settings
            next.pluginTTSBaseURL = value
            store.updateSettings(next)
        }
        .onChange(of: prompt) { _, value in
            var next = store.settings
            next.pluginTTSPrompt = value
            store.updateSettings(next)
        }
    }

    private var ttsProviderBinding: Binding<String> {
        Binding(get: { store.settings.pluginTTSProvider }, set: { value in
            var next = store.settings
            next.pluginTTSProvider = normalizeSpeechProviderID(value)
            next.pluginTTSBaseURL = defaultSpeechTTSBaseURL(for: next.pluginTTSProvider)
            next.pluginTTSModel = defaultSpeechTTSModel(for: next.pluginTTSProvider)
            next.pluginTTSVoice = defaultSpeechTTSVoice(for: next.pluginTTSProvider)
            store.updateSettings(next)
            loadFromStore()
        })
    }

    private var ttsModelBinding: Binding<String> {
        Binding(get: { store.settings.pluginTTSModel }, set: { value in
            var next = store.settings
            next.pluginTTSModel = value
            store.updateSettings(next)
        })
    }

    private var ttsVoiceBinding: Binding<String> {
        Binding(get: { store.settings.pluginTTSVoice }, set: { value in
            var next = store.settings
            next.pluginTTSVoice = value
            store.updateSettings(next)
        })
    }

    private func loadFromStore() {
        apiKey = store.settings.pluginTTSAPIKey
        baseURL = store.settings.pluginTTSBaseURL
        prompt = store.settings.pluginTTSPrompt
    }
}

struct SpeechToTextPluginPane: View {
    @Environment(ChatStore.self) private var store
    @State private var apiKey = ""
    @State private var baseURL = ""

    private var selectedProvider: String {
        store.settings.pluginSTTProvider
    }

    private var requiresAPIKey: Bool {
        speechProviderRequiresAPIKey(selectedProvider)
    }

    private var modelLabel: String {
        normalizeSpeechProviderID(selectedProvider) == SpeechServiceProvider.system.rawValue ? "识别语言" : "模型"
    }

    var body: some View {
        SettingsGroupedForm {
            Section("连接") {
                Picker("提供商", selection: sttProviderBinding) {
                    ForEach(SpeechServiceProvider.allCases) { provider in
                        Text(provider.title).tag(provider.rawValue)
                    }
                }
                if requiresAPIKey {
                    SecureField("API 密钥", text: $apiKey)
                    TextField("API 地址", text: $baseURL)
                } else {
                    Text("使用 macOS 内置语音识别，无需 API Key。首次使用需允许语音识别权限。")
                        .font(.system(size: SettingsMetrics.smallCaptionSize))
                        .foregroundStyle(.secondary)
                }
            }
            Section(modelLabel) {
                Picker(modelLabel, selection: sttModelBinding) {
                    ForEach(speechSTTModels(for: selectedProvider), id: \.self) { model in
                        Text(sttModelTitle(model)).tag(model)
                    }
                }
            }
            Section {
                Toggle("将录音作为文件附加", isOn: sttFileBinding)
            }
        }
        .settingsPageTitle("语音转文本")
        .onAppear(perform: loadFromStore)
        .onChange(of: apiKey) { _, value in
            var next = store.settings
            next.pluginSTTAPIKey = normalizeAPIKey(value)
            store.updateSettings(next)
        }
        .onChange(of: baseURL) { _, value in
            var next = store.settings
            next.pluginSTTBaseURL = value
            store.updateSettings(next)
        }
    }

    private var sttProviderBinding: Binding<String> {
        Binding(get: { store.settings.pluginSTTProvider }, set: { value in
            var next = store.settings
            next.pluginSTTProvider = normalizeSpeechProviderID(value)
            next.pluginSTTBaseURL = defaultSpeechSTTBaseURL(for: next.pluginSTTProvider)
            next.pluginSTTModel = defaultSpeechSTTModel(for: next.pluginSTTProvider)
            store.updateSettings(next)
            loadFromStore()
        })
    }

    private var sttModelBinding: Binding<String> {
        Binding(get: { store.settings.pluginSTTModel }, set: { value in
            var next = store.settings
            next.pluginSTTModel = value
            store.updateSettings(next)
        })
    }

    private var sttFileBinding: Binding<Bool> {
        Binding(get: { store.settings.pluginSTTAddRecordingAsFile }, set: { value in
            var next = store.settings
            next.pluginSTTAddRecordingAsFile = value
            store.updateSettings(next)
        })
    }

    private func sttModelTitle(_ model: String) -> String {
        if normalizeSpeechProviderID(selectedProvider) == SpeechServiceProvider.system.rawValue {
            return systemSpeechLocaleTitle(model)
        }
        return model
    }

    private func loadFromStore() {
        apiKey = store.settings.pluginSTTAPIKey
        baseURL = store.settings.pluginSTTBaseURL
    }
}

struct VisionHelperPluginPane: View {
    @Environment(ChatStore.self) private var store

    private var configuredProviders: [ProviderMeta] {
        store.configuredVisionProviders()
    }

    private var visionModels: [String] {
        store.visionPluginModels(for: store.settings.pluginVisionProvider)
    }

    var body: some View {
        SettingsGroupedForm {
            Section {
                Text("配置辅助视觉模型，为不支持图片的模型生成图片描述。")
                    .font(.system(size: SettingsMetrics.smallCaptionSize))
                    .foregroundStyle(.secondary)
            }
            if configuredProviders.isEmpty {
                Section {
                    Text("请先在「提供商」中配置 API Key，并添加支持识图的模型（如 gpt-4o、gpt-4.1-mini、gemini-2.0-flash）。")
                        .font(.system(size: SettingsMetrics.smallCaptionSize))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("模型") {
                    Picker("提供商", selection: visionProviderBinding) {
                        ForEach(configuredProviders) { provider in
                            Text(provider.title).tag(provider.id)
                        }
                    }
                    Picker("模型", selection: visionModelBinding) {
                        ForEach(visionModels, id: \.self) { model in
                            Text(modelShortName(model)).tag(model)
                        }
                    }
                }
            }
        }
        .settingsPageTitle("辅助视觉模型")
        .onAppear(perform: syncVisionPluginSelection)
    }

    private var visionProviderBinding: Binding<String> {
        Binding(get: { store.settings.pluginVisionProvider }, set: { value in
            var next = store.settings
            next.pluginVisionProvider = value
            let available = store.visionPluginModels(for: value)
            if !available.contains(next.pluginVisionModel) {
                next.pluginVisionModel = available.first ?? next.pluginVisionModel
            }
            store.updateSettings(next)
        })
    }

    private var visionModelBinding: Binding<String> {
        Binding(get: { store.settings.pluginVisionModel }, set: { value in
            var next = store.settings
            next.pluginVisionModel = value
            store.updateSettings(next)
        })
    }

    private func syncVisionPluginSelection() {
        guard !configuredProviders.isEmpty else { return }
        var next = store.settings
        if !configuredProviders.contains(where: { $0.id == next.pluginVisionProvider }) {
            next.pluginVisionProvider = configuredProviders[0].id
        }
        let available = store.visionPluginModels(for: next.pluginVisionProvider)
        if !available.contains(next.pluginVisionModel) {
            next.pluginVisionModel = available.first ?? next.pluginVisionModel
        }
        if next != store.settings {
            store.updateSettings(next)
        }
    }
}

struct MapPluginPane: View {
    @Environment(ChatStore.self) private var store
    @State private var apiKey = ""

    var body: some View {
        SettingsGroupedForm {
            Section("提供商") {
                Picker("地图服务", selection: mapProviderBinding) {
                    ForEach(MapProviderOption.allCases) { p in Text(p.title).tag(p.rawValue) }
                }
            }
            Section("凭据") {
                SecureField("Yandex API 密钥", text: $apiKey)
            }
        }
        .settingsPageTitle("地图")
        .onAppear { apiKey = store.settings.pluginMapAPIKey }
        .onChange(of: apiKey) { _, v in var n = store.settings; n.pluginMapAPIKey = normalizeAPIKey(v); store.updateSettings(n) }
    }

    private var mapProviderBinding: Binding<String> {
        Binding(get: { store.settings.pluginMapProvider }, set: { v in
            var n = store.settings; n.pluginMapProvider = v; store.updateSettings(n)
        })
    }
}

struct NetworkSettingsPane: View {
    @Environment(ChatStore.self) private var store

    var body: some View {
        SettingsGroupedForm {
            Section("搜索引擎") {
                Toggle("启用联网搜索", isOn: webSearchBinding)
                Picker("引擎", selection: engineBinding) {
                    ForEach(WebSearchEngineOption.allCases) { e in Text(e.title).tag(e.rawValue) }
                }
                SecureField("Tavily API 密钥", text: tavilyKeyBinding)
            }
            Section("参数") {
                TextField("搜索语言", text: langBinding)
                Stepper("结果数：\(store.settings.webSearchResultLimit)", value: limitBinding, in: 3...15)
                TextField("排除域名", text: excludeBinding)
            }
        }
        .settingsPageTitle("联网搜索")
    }

    private var webSearchBinding: Binding<Bool> {
        Binding(get: { store.settings.webSearchEnabled }, set: { v in var n = store.settings; n.webSearchEnabled = v; store.updateSettings(n) })
    }

    private var engineBinding: Binding<String> {
        Binding(get: { store.settings.webSearchEngine }, set: { v in var n = store.settings; n.webSearchEngine = v; store.updateSettings(n) })
    }

    private var tavilyKeyBinding: Binding<String> {
        Binding(get: { store.settings.tavilyAPIKey }, set: { v in var n = store.settings; n.tavilyAPIKey = normalizeAPIKey(v); store.updateSettings(n) })
    }

    private var langBinding: Binding<String> {
        Binding(get: { store.settings.webSearchLang }, set: { v in var n = store.settings; n.webSearchLang = v; store.updateSettings(n) })
    }

    private var limitBinding: Binding<Int> {
        Binding(get: { store.settings.webSearchResultLimit }, set: { v in var n = store.settings; n.webSearchResultLimit = v; store.updateSettings(n) })
    }

    private var excludeBinding: Binding<String> {
        Binding(get: { store.settings.webSearchExcludeSites }, set: { v in var n = store.settings; n.webSearchExcludeSites = v; store.updateSettings(n) })
    }
}
