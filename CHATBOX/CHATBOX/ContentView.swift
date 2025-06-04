//
//  ContentView.swift
//  CHATBOX
//
//  Created by Ruixiang on 2025/6/1.
//

//
//  ContentView.swift
//  CHATBOX
//
//  Created by Ruixiang on 2025/6/1.
//

import SwiftUI
import AppKit
import MarkdownUI
/// A helper to wrap NSVisualEffectView for SwiftUI
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
}
import Foundation


// MARK: - ChatGPT 主题色
extension Color {
    /// ChatGPT 品牌黑灰色
    static let chatGPTGreen = Color(red: 52/255, green: 53/255, blue: 65/255) // 修改为黑灰色
    /// ChatGPT 侧边栏背景色
    static let chatGPTSidebarBackground = Color(red: 244/255, green: 244/255, blue: 245/255)
    /// ChatGPT 亮色主题背景（#F7F7F8）
    static let chatGPTLightBackground = Color(red: 247/255, green: 247/255, blue: 248/255)
    /// ChatGPT 暗色主题背景（#343541）
    static let chatGPTDarkBackground = Color(red: 52/255, green: 53/255, blue: 65/255)
    /// ChatGPT 助手气泡浅灰背景（#F7F7F8）
    static let chatGPTAssistantBubble = Color(red: 247/255, green: 247/255, blue: 248/255)
    /// ChatGPT 用户气泡背景色
    static let chatGPTUserBubble = Color(red: 52/255, green: 53/255, blue: 65/255) // 修改为黑灰色
    /// ChatGPT 代码块背景色
    static let chatGPTCodeBackground = Color(red: 40/255, green: 44/255, blue: 52/255)
    /// ChatGPT 输入框背景色
    static let chatGPTInputBackground = Color(red: 64/255, green: 65/255, blue: 79/255)
    /// ChatGPT 输入框文本颜色
    static let chatGPTInputText = Color.white
    /// ChatGPT 边框颜色
    static let chatGPTBorder = Color(red: 217/255, green: 217/255, blue: 217/255)
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

// MARK: - 按钮按压效果
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 外观模式
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色模式"
        case .dark:   return "深色模式"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - 聊天消息模型
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String          // 允许在气泡中逐字追加
    let isUser: Bool
    let timestamp = Date()
}

// MARK: - 聊天会话模型
struct ChatSession: Identifiable {
    let id = UUID()
    var title: String
    var messages: [ChatMessage]
    var lastUpdated = Date()
}

// MARK: - 模型信息
struct ModelInfo: Identifiable, Hashable {
    /// 用于 API 请求的实际模型 ID
    let id: String
    /// UI 中展示给用户的名称（可自定义）
    let displayName: String

    var identifier: String { id }
    var _id: String { id }  // 便于 `tag` 绑定
}

// MARK: - AI模型提供商
enum AIModelProvider: String, CaseIterable, Identifiable {
    case openAI        = "OpenAI"
    case siliconFlowAI = "SILICONFLOWAI"
    case googleAI      = "Google AI"
    
    var isMain: Bool {
        switch self {
        case .openAI: return true
        case .siliconFlowAI: return true
        case .googleAI: return true
        }
    }

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .openAI:        return "OpenAI"
        case .siliconFlowAI: return "硅基流动"
        case .googleAI:      return "Google AI"
        }
    }

    /// 系统图标 (SF Symbols)
    var icon: String {
        switch self {
        case .openAI:        return "sparkles"
        case .siliconFlowAI: return "magnifyingglass.circle"
        case .googleAI:      return "g.circle"
        }
    }

    /// 每个提供商可用模型 (id + display name)
    var availableModels: [ModelInfo] {
        switch self {
        case .openAI:
            return [
                ModelInfo(id: "gpt-4.1",       displayName: "GPT‑4.1"),
                ModelInfo(id: "gpt-4.1-mini",  displayName: "GPT‑4.1 Mini"),
                ModelInfo(id: "gpt-4.1-nano",  displayName: "GPT‑4.1 Nano"),
                ModelInfo(id: "gpt-4o",        displayName: "GPT‑4o"),
                ModelInfo(id: "gpt-4o-mini",   displayName: "GPT‑4o Mini")
            ]
        case .siliconFlowAI:
            return [
                ModelInfo(id: "deepseek-ai/DeepSeek-R1", displayName: "DeepSeek R1"),
                ModelInfo(id: "deepseek-ai/DeepSeek-V3", displayName: "DeepSeek V3")
            ]
        case .googleAI:
            return [
                ModelInfo(id: "gemini-2.5-flash-preview-05-20", displayName: "Gemini-2.5-flash-preview-05-20"),
                ModelInfo(id: "gemini-2.0-flash", displayName: "Gemini 2.0 Flash"),
                ModelInfo(id: "gemini-2.0-flash-lite", displayName: "Gemini 2.0 Flash Lite")
            ]
        }
    }

    /// 默认模型
    var defaultModel: String {
        availableModels.first?.id ?? "default"
    }

    /// 对应 API 端点
    var apiEndpoint: String {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .siliconFlowAI:
            // 硅基流动 API 兼容 OpenAI 路径规范
            return "https://api.siliconflow.cn/v1/chat/completions"
        case .googleAI:
            // 这是 Google Generative Language API 的基础路径，具体模型由调用处拼接
            return "https://generativelanguage.googleapis.com/v1beta/models"
        }
    }
}

// MARK: - 聊天服务
actor ChatService {
    private let session = URLSession.shared
    
    /// 读取用户自定义的 API Endpoint；若为空则使用默认值
    private func endpoint(for provider: AIModelProvider) -> String {
        if let custom = UserDefaults.standard.string(forKey: "\(provider.rawValue)Endpoint"),
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return provider.apiEndpoint
    }

    // 发送消息到选定的API提供商
    func sendMessage(_ text: String, via provider: AIModelProvider, model: String) async throws -> String {
        switch provider {
        case .openAI:
            return try await sendToOpenAI(text, model: model, provider: provider)
        case .siliconFlowAI:
            return try await sendToSiliconFlow(text, model: model)
        case .googleAI:
            return try await sendToGemini(text, model: model)
        }
    }
    
    // MARK: - OpenAI 实现
    private func sendToOpenAI(_ text: String, model: String, provider: AIModelProvider) async throws -> String {
        guard let apiKey = getAPIKey(for: provider) else {
            throw APIError.missingAPIKey
        }

        let url = URL(string: endpoint(for: provider))!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages: [[String: Any]] = [
            ["role": "user", "content": text]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response: response)

        // 解析响应
        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(OpenAIResponse.self, from: data)

        return result.choices.first?.message.content ?? "没有收到响应"
    }
    
    // MARK: - SiliconFlow 实现
    private func sendToSiliconFlow(_ text: String, model: String) async throws -> String {
        guard let apiKey = getAPIKey(for: .siliconFlowAI) else {
            throw APIError.missingAPIKey
        }

        let url = URL(string: endpoint(for: .siliconFlowAI))!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let messages: [[String: Any]] = [
            ["role": "user", "content": text]
        ]

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response: response)

        // 解析响应（与OpenAI类似）
        struct SiliconFlowResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(SiliconFlowResponse.self, from: data)

        return result.choices.first?.message.content ?? "没有收到响应"
    }
    
    // MARK: - Gemini 实现
    private func sendToGemini(_ text: String, model: String) async throws -> String {
        guard let apiKey = getAPIKey(for: .googleAI) else {
            throw APIError.missingAPIKey
        }

        let base = endpoint(for: .googleAI).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urlString = "\(base)/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": text]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response: response)

        struct GeminiResponse: Codable {
            struct Candidate: Codable {
                struct Content: Codable {
                    struct Part: Codable { let text: String }
                    let parts: [Part]
                }
                let content: Content
            }
            let candidates: [Candidate]
        }

        let result = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return result.candidates.first?.content.parts.first?.text ?? "没有收到响应"
    }
    
    // MARK: - 辅助方法
    private func getAPIKey(for provider: AIModelProvider) -> String? {
        let key = UserDefaults.standard.string(forKey: "\(provider.rawValue)Key")
        return key?.isEmpty == false ? key : nil
    }
    
    private func validateResponse(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    enum APIError: Error, LocalizedError {
        case missingAPIKey
        case invalidResponse
        case serverError(statusCode: Int)
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "缺少API密钥，请在设置中配置"
            case .invalidResponse:
                return "收到无效的服务器响应"
            case .serverError(let statusCode):
                return "服务器错误 (HTTP \(statusCode))"
            }
        }
    }
}

// MARK: - 视图模型
@MainActor final class ChatViewModel: ObservableObject {
    @Published var selectedMainModel: ModelInfo = ModelInfo(id: "gpt-4o", displayName: "GPT‑4o")
    
    var mainModels: [ModelInfo] {
        return [
            ModelInfo(id: "gpt-4o",              displayName: "GPT‑4o (OpenAI)"),
            ModelInfo(id: "gpt-4.1",             displayName: "GPT‑4.1 (OpenAI)"),
            ModelInfo(id: "gpt-4.1-mini",        displayName: "GPT‑4.1 Mini (OpenAI)"),
            ModelInfo(id: "gpt-4.1-nano",        displayName: "GPT‑4.1 Nano (OpenAI)"),
            ModelInfo(id: "deepseek-ai/DeepSeek-R1", displayName: "DeepSeek R1"),
            ModelInfo(id: "deepseek-ai/DeepSeek-V3", displayName: "DeepSeek V3"),
            ModelInfo(id: "gemini-2p5-flash",    displayName: "Gemini 2.5 Flash")
        ]
    }
    @Published var sessions: [ChatSession] = []
    @Published var currentSessionID: UUID?
    @Published var selectedProvider: AIModelProvider = .openAI
    @Published var selectedModel: String = AIModelProvider.openAI.defaultModel
    /// 当前选中模型的友好名称
    var selectedModelDisplayName: String {
        selectedProvider
            .availableModels
            .first(where: { $0.id == selectedModel })?
            .displayName ?? selectedModel
    }
    @Published var isLoading = false
    @Published var thinkingSteps: [String] = []
    /// Computed property to check if the current model is DeepSeek V1
    var isDeepSeekV1Model: Bool {
        return selectedProvider == .siliconFlowAI && selectedModel == "deepseek-ai/DeepSeek-R1"
    }
    /// 是否为思考型模型（名称含 thinking）
    @Published var isThinkingModel = false
    /// 思考开始时间，用于计时显示
    @Published var thinkingStart: Date?
    @Published var errorMessage: String?
    @AppStorage("appearanceModeRaw") var appearanceModeRaw: String = AppearanceMode.system.rawValue
    private let service = ChatService()
    /// 当前 AI 回复任务（便于取消）
    private var messageTask: Task<Void, Never>? = nil

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: appearanceModeRaw) ?? .system }
        set { appearanceModeRaw = newValue.rawValue }
    }

    init() {
        // 加载保存的模型选择
        if let savedProvider = UserDefaults.standard.string(forKey: "selectedProvider"),
           let provider = AIModelProvider(rawValue: savedProvider) {
            selectedProvider = provider
        }

        if let savedModel = UserDefaults.standard.string(forKey: "selectedModel") {
            selectedModel = savedModel
        } else {
            selectedModel = selectedProvider.defaultModel
        }

        // 创建默认会话
        createNewSession()
    }
    
    /// 当前会话的消息列表
    var messages: [ChatMessage] {
        get { sessions.first { $0.id == currentSessionID }?.messages ?? [] }
        set {
            guard let idx = sessions.firstIndex(where: { $0.id == currentSessionID }) else { return }
            sessions[idx].messages = newValue
            sessions[idx].lastUpdated = Date()
            // 若尚未生成标题，则使用首条用户消息作为摘要
            if sessions[idx].title.isEmpty {
                if let firstUser = newValue.first(where: { $0.isUser }) {
                    let raw = firstUser.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    sessions[idx].title = raw.count > 30 ? String(raw.prefix(30)) + "…" : raw
                }
            }
        }
    }
    
    /// 创建新会话
    func createNewSession() {
        let session = ChatSession(title: "", messages: [])
        sessions.insert(session, at: 0)
        currentSessionID = session.id
        errorMessage = nil
    }
    
    /// 删除会话
    func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        
        // 如果删除的是当前会话，切换到第一个会话
        if currentSessionID == id {
            currentSessionID = sessions.first?.id
        }
    }
    
    /// 发送消息
    func sendMessage(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        
        // 检查API密钥是否配置
        if !isAPIKeyConfigured(for: selectedProvider) {
            errorMessage = "请先在设置中配置 \(selectedProvider.displayName) 的API密钥"
            return
        }

        // 判断是否为思考型模型
        // 规则：模型 ID 含 "thinking" 或来自 DeepSeek（SiliconFlowAI）
        isThinkingModel = selectedModel.lowercased().contains("thinking") ||
                          selectedProvider == .siliconFlowAI
        
        // 如果没有会话，创建一个
        if sessions.isEmpty {
            createNewSession()
        }
        
        // 添加用户消息
        var currentMessages = messages
        let userMessage = ChatMessage(text: trimmedText, isUser: true)
        currentMessages.append(userMessage)
        messages = currentMessages
        
        // 发送到API
        if isThinkingModel {
            thinkingStart = Date()
        }
        messageTask = Task {
            do {
                isLoading = true
                errorMessage = nil
                
                let response = try await service.sendMessage(trimmedText, via: selectedProvider, model: selectedModel)
                
                // 先插入占位回复，后续逐字填充
                var updated = messages
                var aiPlaceholder = ChatMessage(text: "", isUser: false)
                updated.append(aiPlaceholder)
                messages = updated
                
                // 获取待更新的索引
                let idx = messages.count - 1
                
                // 逐字符追加，模拟 ChatGPT 打字效果
                for ch in response {
                    if Task.isCancelled { break }
                    try await Task.sleep(nanoseconds: 30_000_000)   // 30 ms / 字符
                    await MainActor.run {
                        var current = self.messages
                        current[idx].text.append(ch)
                        self.messages = current
                    }
                }
                
                isLoading = false
                isThinkingModel = false
                thinkingStart = nil
                thinkingSteps = [] // Reset steps
                messageTask = nil
            } catch {
                isLoading = false
                isThinkingModel = false
                thinkingStart = nil
                thinkingSteps = [] // Reset steps
                messageTask = nil
                errorMessage = error.localizedDescription
                
                // 添加错误消息
                var updatedMessages = messages
                let errorMessage = ChatMessage(text: "⚠️ 错误: \(error.localizedDescription)", isUser: false)
                updatedMessages.append(errorMessage)
                messages = updatedMessages
            }
        }
    }
    
    /// 检查API密钥是否配置
    func isAPIKeyConfigured(for provider: AIModelProvider) -> Bool {
        let key = UserDefaults.standard.string(forKey: "\(provider.rawValue)Key")
        return key?.isEmpty == false
    }
    
    /// 更新选中的模型提供商
    func selectProvider(_ provider: AIModelProvider) {
        selectedProvider = provider
        selectedModel = provider.defaultModel
        
        // 保存选择
        UserDefaults.standard.set(provider.rawValue, forKey: "selectedProvider")
        UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
    }
    
    /// 终止当前 AI 回复
    func cancelGeneration() {
        messageTask?.cancel()
        messageTask = nil
        isLoading = false
        isThinkingModel = false
        thinkingStart = nil
        thinkingSteps = [] // Reset steps
    }
}

// MARK: - 布局常量
struct LayoutConstants {
    static let padding: CGFloat = 16
    static let cornerRadius: CGFloat = 12
    static let messageSpacing: CGFloat = 8
    static let sessionItemPadding: EdgeInsets = .init(top: 8, leading: 12, bottom: 8, trailing: 12)
    static let inputCornerRadius: CGFloat = 20
    static let inputHeight: CGFloat = 40
}

// MARK: - 主视图
struct ContentView: View {
    @StateObject private var viewModel: ChatViewModel
    @State private var inputText: String = ""
    @State private var showingSettings = false
    @Environment(\.colorScheme) private var colorScheme // 获取当前的颜色方案
    @State private var timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var searchText: String = ""
    
    init() {
        _viewModel = StateObject(wrappedValue: ChatViewModel())
    }
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // 搜索框
                searchBarView
                
                // 会话列表
                sessionListView
                Spacer()
                HStack {
                    settingsButton        // 设置按钮移到侧边栏底部
                    Spacer()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            // 根据 appearanceMode 切换侧边栏背景色
            .background(colorScheme == .dark ? Color.chatGPTDarkBackground : Color.chatGPTSidebarBackground)
            .frame(minWidth: 240)
        } detail: {
            VStack(spacing: 0) {
                // 分界线
                Divider()
                
                // 消息列表
                messageListView
                    .frame(maxHeight: .infinity)
                
                // 错误消息
                errorMessageView
                
                // 输入区域
                inputAreaView
            }
            // 根据 appearanceMode 切换主内容区域背景色
            .background(colorScheme == .dark ? Color.chatGPTDarkBackground : Color.chatGPTLightBackground)
        }
        .frame(minWidth: 800, minHeight: 600)
        .preferredColorScheme(viewModel.appearanceMode.colorScheme)
        .accentColor(.chatGPTGreen)
        .toolbar {
            // 左侧：模型选择菜单
            ToolbarItem(placement: .navigation) {
                modelSelectionMenu
            }

            // ToolbarItem(placement: .principal) { // This item was removed
            //     Spacer(minLength: 0)
            // }

            // 右侧：新建会话按钮，固定最右
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.createNewSession) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.borderless)
                .help("新建会话")
            }
        }
    }
    
    // MARK: - 子视图组件
    
    private var searchBarView: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14))
            TextField("搜索对话", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundColor(colorScheme == .dark ? .white : .black) // 适配搜索框文字颜色
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(colorScheme == .dark ? .darkGray : .controlBackgroundColor)) // 适配搜索框背景
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .offset(y: -1)
    }
    
    private var sessionListView: some View {
        VStack(spacing: 0) {
            Text("会话")
                .font(.headline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredSessions) { session in
                        sessionRowView(session: session)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }
    
    private var filteredSessions: [ChatSession] {
        viewModel.sessions.filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func sessionRowView(session: ChatSession) -> some View {
        HStack(spacing: 10) {
            // Image(systemName: "message") // 左侧信息图标已移除
            //     .foregroundColor(viewModel.currentSessionID == session.id ? .primary : .secondary)
            //     .font(.system(size: 15))
            //     .frame(width: 20, alignment: .center)
            
            Text(session.title.isEmpty ? "新会话" : session.title)
                .font(.system(size: 13))
                .lineLimit(1)
                // 根据是否选中和颜色模式调整文字颜色
                .foregroundColor(viewModel.currentSessionID == session.id ? (colorScheme == .dark ? .white : .primary) : .secondary)
            
            Spacer()
            
            // if viewModel.currentSessionID == session.id { // 右侧对勾已移除
            //     Image(systemName: "checkmark")
            //         .foregroundColor(.primary)
            //         .font(.system(size: 12, weight: .semibold))
            // }
        }
        // 修正 padding 的用法
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(sessionRowBackground(for: session))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.currentSessionID = session.id
        }
        .contextMenu {
            Button(role: .destructive) {
                viewModel.deleteSession(session.id)
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
    }
    
    private func sessionRowBackground(for session: ChatSession) -> some View {
        let isSelected = viewModel.currentSessionID == session.id
        // 使用灰色作为选中背景，如果未选中则透明
        // 深色模式下选中颜色可以更亮一些，或者使用不同的强调色
        let backgroundColor = isSelected ? (colorScheme == .dark ? Color.gray.opacity(0.4) : Color.gray.opacity(0.2)) : Color.clear // 修改背景色
        return RoundedRectangle(cornerRadius: 8).fill(backgroundColor) // 调整圆角以匹配图片
    }
    

    
    private var titleBarViewSimplified: some View {
        HStack {
            Spacer()
            
            // 右侧：新建会话按钮
            Button(action: viewModel.createNewSession) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.borderless)
            .help("新建会话")
        }
        .padding(.leading, 16)   // 保留左侧内边距
        .padding(.vertical, 8)   // 垂直内边距保持
        .background(Color(.windowBackgroundColor))
    }
    
    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(viewModel.messages) { message in
                        MessageCell(message: message)
                            .id(message.id)
                    }
                    
                    // 思考型模型计时提示
                    thinkingIndicatorView
                    
                    // 滚动锚点
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onReceive(timer) { _ in
                // 强制刷新以更新时间戳
                if viewModel.isThinkingModel {
                    // 仅在思考中滚动到底
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        // 根据 appearanceMode 切换消息列表背景色
        .background(colorScheme == .dark ? Color.chatGPTDarkBackground : Color.chatGPTLightBackground)
    }
    
    @ViewBuilder
    private var thinkingIndicatorView: some View {
        Group {
            // Check if the current model is DeepSeek V1 and viewModel is loading or has thinking steps
            if viewModel.isDeepSeekV1Model && (viewModel.isLoading || !viewModel.thinkingSteps.isEmpty) {
                // Define elapsed based on viewModel.thinkingStart, defaulting to 0.0 if nil
                let elapsed = viewModel.thinkingStart.map { Date().timeIntervalSince($0) } ?? 0.0

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                            .controlSize(.small)
                        // Show "思考中" text only if isLoading is true or elapsed time is greater than 0
                        if viewModel.isLoading || elapsed > 0 {
                             Text("思考中 \(String(format: "%.1f", elapsed))s")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    ForEach(viewModel.thinkingSteps, id: \.self) { step in
                        Text("• \(step)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .padding(.leading, 20) // Indent steps
                    }
                }
                .padding(.vertical, 8)
                .id("thinking")
            } else {
                EmptyView() // If not DeepSeek V1 model, or not loading and no steps, show nothing
            }
        }
    }
    
    @ViewBuilder
    private var errorMessageView: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .foregroundColor(.red)
                .padding(.horizontal)
                .padding(.top, 8)
        }
    }
    
    private var inputAreaView: some View {
        HStack(spacing: 8) {
            TextField("询问任何问题...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundColor(colorScheme == .dark ? .white : .primary) // 输入文字颜色
                .lineLimit(1...10) // 修改这里，将行数限制从1...6改为1...10
                .submitLabel(.send)
                .onSubmit { sendMessage() }
                .padding(.vertical, 10) // 为TextField增加一些垂直内边距，使其看起来更高
            
            Button(action: {
                if viewModel.isLoading {
                    viewModel.cancelGeneration() // 确保这个方法存在于 ViewModel 中
                } else {
                    sendMessage()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(colorScheme == .dark ? Color.gray.opacity(0.5) : Color.black) // 按钮背景改为黑色，根据图片, 深色模式下调整
                        .frame(width: 32, height: 32) // 按钮大小调整以匹配图片感觉
                    Image(systemName: viewModel.isLoading ? "stop.fill" : "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain) // 使用 plain button style 避免额外的默认样式
            .disabled(sendButtonDisabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8) // 修改这里，将垂直内边距从12改为8
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95)) // 输入框背景色，深色模式适配
                .stroke(Color.gray.opacity(0.3), lineWidth: 1) // 边框颜色，深色模式适配
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .offset(y: -1) // 整体向上移动10格
    }
    
    
    private var sendButtonDisabled: Bool {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !viewModel.isLoading && trimmedText.isEmpty
    }
    
    private var settingsButton: some View {
        Button {
            showingSettings.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                Text("API设置")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.borderless)
        .sheet(isPresented: $showingSettings) {
            APIPreferencesView(viewModel: viewModel)
        }
    }
    
    // 将Menu提取为计算属性
    private var modelSelectionMenu: some View {
        Menu {
            ForEach(AIModelProvider.allCases) { provider in
                Section {
                    ForEach(provider.availableModels) { model in
                        modelSelectionButton(provider: provider, model: model)
                    }
                } header: {
                    Label(provider.displayName, systemImage: provider.icon)
                        .foregroundColor(.primary)
                        .font(.headline)
                }
            }
        } label: {
            modelSelectionMenuLabel
        }
        .menuStyle(.borderlessButton)
    }
    
    private func modelSelectionButton(provider: AIModelProvider, model: ModelInfo) -> some View {
        Button {
            // 先切换到对应提供商，再设置模型
            viewModel.selectProvider(provider)
            viewModel.selectedModel = model.id
        } label: {
            HStack {
                Text(model.displayName)
                    .foregroundColor(.primary)
                    .font(.body)
                // 当前选中的模型右侧打勾
                if viewModel.selectedProvider == provider &&
                    viewModel.selectedModel == model.id {
                    Image(systemName: "checkmark")
                        .foregroundColor(.chatGPTGreen)
                }
            }
        }
    }
    
    // MARK: - 模型选择按钮样式（显示大模型提供商 + 具体模型名称）
    private var modelSelectionMenuLabel: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 上面：模型名称（适中的字重）
            Text(viewModel.selectedModelDisplayName)
                .font(.system(size: 14, weight: .semibold, design: .default))
                .foregroundColor(.primary)
            // 下面：提供商名称（较轻的字重）
            Text(viewModel.selectedProvider.displayName)
                .font(.system(size: 12, weight: .medium, design: .default))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separatorColor), lineWidth: 0.5)
        )
    }

    /// 提取模型 ID 中的简短版本标签（如 `gpt-4o` -> “o”, `gpt-4.1-mini` -> “mini”）
    private func versionTag(for modelId: String) -> String? {
        // 以 “/” 或 “:” 或 “-” 拆分，然后找最后一段
        let delimiters = CharacterSet(charactersIn: "/:-")
        let parts = modelId
            .components(separatedBy: delimiters)
            .filter { !$0.isEmpty }

        guard let last = parts.last else { return nil }

        // 若是纯数字或常见前缀则继续往前取
        if last.lowercased().hasPrefix("gpt") || last.lowercased().hasPrefix("gemini") {
            return parts.dropLast().last
        }
        return last
    }

    // MARK: 消息单元
    struct MessageCell: View {
        let message: ChatMessage
        @Environment(\.colorScheme) private var colorScheme // 获取当前的颜色方案

        /// 动态限制气泡最大宽度（macOS 用 NSScreen，iOS 用 UIScreen）
        private var maxBubbleWidth: CGFloat {
#if os(macOS)
            return (NSScreen.main?.visibleFrame.width ?? 800) * 0.7
#else
            return UIScreen.main.bounds.width * 0.7
#endif
        }

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                // 仅保留消息气泡，不再显示头像
                messageBubble
            }
            .padding(.horizontal, 8)
        }

        private var assistantAvatar: some View {
            Image(systemName: "sparkles")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.chatGPTGreen)
                .clipShape(Circle())
        }

        private var userAvatar: some View {
            Image(systemName: "person.fill")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Color.blue)
                .clipShape(Circle())
        }

        private var safeMessageText: String {
            let maxLength = 20000
            let cleaned = message.text.prefix(maxLength)
            if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "⚠️ 内容为空或不支持显示。"
            }
            if message.text.count > maxLength {
                return "⚠️ 内容过长，无法完整显示。"
            }
            return String(cleaned)
        }

        private var messageBubble: some View {
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Markdown(safeMessageText)
                    // .markdownStyle(.default) // <- 移除这一行
                    .multilineTextAlignment(message.isUser ? .trailing : .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(messageBubbleBackground)
                    .foregroundColor(message.isUser ? .white : (colorScheme == .dark ? .white : .primary))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity,
                           alignment: message.isUser ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: maxBubbleWidth, alignment: message.isUser ? .trailing : .leading)
        }

        private var messageBubbleBackground: some View {
            // 用户消息气泡颜色保持不变，助手消息气泡颜色根据主题调整
            let backgroundColor = message.isUser ? Color.gray.opacity(0.3) : (colorScheme == .dark ? Color(white: 0.25) : Color.chatGPTAssistantBubble)
            return RoundedRectangle(cornerRadius: 16).fill(backgroundColor)
        }
    }
    
    // MARK: 发送消息
    private func sendMessage() {
        viewModel.sendMessage(inputText)
        inputText = ""
    }
}

// MARK: - API 设置面板
struct APIPreferencesView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var selectedProvider: AIModelProvider = .openAI
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            VisualEffectView(material: .sidebar, blendingMode: .withinWindow)
                .ignoresSafeArea()
            content
                .padding(0)
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 0) {
            // 左侧提供商列表
            VStack(spacing: 0) {
                Text("选择提供商")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                Divider()
                providerListRows
                Spacer()
            }
            .frame(width: 200)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.9))

            Divider()
                .background(Color(.separatorColor))

            // 右侧设置表单和底部按钮
            settingsForm
        }
    }

    private var providerListRows: some View {
        VStack(spacing: 4) {
            ForEach([AIModelProvider.openAI, .siliconFlowAI, .googleAI], id: \.self) { provider in
                HStack {
                    Label(provider.displayName, systemImage: provider.icon)
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
                .background(
                    Group {
                        if selectedProvider == provider {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.chatGPTGreen.opacity(0.2))
                        } else {
                            Color.clear
                        }
                    }
                )
                .cornerRadius(8)
                .foregroundColor(selectedProvider == provider ? .chatGPTGreen : (colorScheme == .dark ? .white : .primary))
                .onTapGesture {
                    selectedProvider = provider
                }
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 8)
    }

    private var settingsForm: some View {
        VStack {
            GroupBox(label: Text(selectedProvider.displayName).font(.headline)) {
                VStack(alignment: .leading, spacing: 12) {
                    apiKeyField
                        .padding(.horizontal)
                    apiEndpointField
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
        }
        .padding()
    }

    private var apiKeyField: some View {
        TextField("API Key", text: .init(
            get: { UserDefaults.standard.string(forKey: "\(selectedProvider.rawValue)Key") ?? "" },
            set: { UserDefaults.standard.set($0, forKey: "\(selectedProvider.rawValue)Key") }
        ))
        .textFieldStyle(.roundedBorder)
        .foregroundColor(colorScheme == .dark ? .primary : .primary)
    }

    private var apiEndpointField: some View {
        TextField("API Base URL", text: .init(
            get: { UserDefaults.standard.string(forKey: "\(selectedProvider.rawValue)Endpoint") ?? selectedProvider.apiEndpoint },
            set: { UserDefaults.standard.set($0, forKey: "\(selectedProvider.rawValue)Endpoint") }
        ))
        .textFieldStyle(.roundedBorder)
        .disabled(selectedProvider == .openAI)
        .foregroundColor(colorScheme == .dark ? .primary : .primary)
    }

}


