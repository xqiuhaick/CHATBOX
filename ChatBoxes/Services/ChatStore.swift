import Foundation
import Observation

@MainActor
@Observable
final class ChatStore {
    private let storage = StorageService.shared
    private let api = ChatAPIService.shared
    private let webSearch = WebSearchService.shared
    private let speech = ChatBoxSpeechTranslationService.shared

    var sessions: [ChatSession] = []
    var settings = AppSettings()
    var activeSessionID: String = ""
    var draftToEdit: String = ""

    private var generatingSessionID = ""
    private var generatingMessageID = ""
    private var reasoningStartMS: [String: TimeInterval] = [:]

    init() {
        load()
    }

    var activeSession: ChatSession? {
        sessions.first(where: { $0.id == activeSessionID }) ?? sessions.first
    }

    func load() {
        sessions = storage.getSessions()
        settings = normalizeSettings(storage.getSettings())
        if sessions.isEmpty {
            sessions = [createSession()]
            persistSessions()
        }
        if activeSessionID.isEmpty {
            activeSessionID = sessions.first?.id ?? ""
        }
    }

    func createAndSelectSession() {
        let session = createSession()
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        persistSessions()
    }

    func selectSession(_ sessionID: String) {
        activeSessionID = sessionID
    }

    func deleteSession(_ sessionID: String) {
        guard sessions.count > 1 else { return }
        sessions.removeAll { $0.id == sessionID }
        if activeSessionID == sessionID {
            activeSessionID = sessions.first?.id ?? ""
        }
        persistSessions()
    }

    func renameSession(_ sessionID: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        sessions[index].title = trimmed
        sessions[index].updatedAt = Date().timeIntervalSince1970 * 1000
        persistSessions()
    }

    func requestModify(_ content: String) {
        draftToEdit = content
    }

    func updateSettings(_ next: AppSettings) {
        settings = normalizeSettings(next)
        storage.saveSettings(settings)
    }

    func clearStoredAPISecrets() {
        settings.openAIAPIKey = ""
        settings.deepSeekAPIKey = ""
        settings.tavilyAPIKey = ""
        settings.apiKey = ""
        settings.providerAPIKeysJSON = "{}"
        storage.saveSettings(settings)
    }

    func stopGenerating() {
        api.stop()
        finishAssistantMessage(sessionID: generatingSessionID, messageID: generatingMessageID)
        persistSessions()
    }

    func sendMessage(
        content: String,
        imageDataURL: String = "",
        fileName: String = "",
        fileExt: String = "",
        fileText: String = "",
        useWebSearch: Bool = false
    ) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && imageDataURL.isEmpty && fileName.isEmpty { return }

        let visionAdjusted = await visionAssistIfNeeded(imageDataURL: imageDataURL, userText: trimmed)
        let resolvedImage = visionAdjusted.imageDataURL
        let resolvedText = visionAdjusted.userText

        let shouldSearch = useWebSearch && settings.webSearchEnabled
        var userMessage: ChatMessage
        if !resolvedImage.isEmpty {
            userMessage = createUserMessageWithImage(content: resolvedText.isEmpty ? "[图片]" : resolvedText, imageDataURL: resolvedImage)
        } else if !fileName.isEmpty {
            userMessage = createUserMessageWithFile(content: resolvedText.isEmpty ? "[文件] \(fileName)" : resolvedText, fileName: fileName, fileExt: fileExt, fileText: fileText)
        } else {
            userMessage = createUserMessage(content: resolvedText)
        }
        userMessage.webSearchRequested = shouldSearch

        let expectReasoning = isReasoningModel(settings.model)
        let assistantMessage = createEmptyAssistantMessage(expectReasoning: expectReasoning)
        let previousCount = sessions[sessionIndex].messages.count
        let sessionID = sessions[sessionIndex].id

        sessions[sessionIndex].messages.append(userMessage)
        sessions[sessionIndex].messages.append(assistantMessage)
        if sessions[sessionIndex].title == "新对话", settings.pluginTitleUpdateMode != .manualOnly {
            sessions[sessionIndex].title = deriveTitle(from: resolvedText.isEmpty ? (resolvedImage.isEmpty ? "新对话" : "图片对话") : resolvedText)
        }
        sessions[sessionIndex].updatedAt = Date().timeIntervalSince1970 * 1000
        generatingSessionID = sessionID
        generatingMessageID = assistantMessage.id
        persistSessions()

        Task { await maybeAutoUpdateTitle(sessionID: sessionID, userContent: resolvedText, previousMessageCount: previousCount) }
        await generateAssistantReply(sessionID: sessionID, assistantMessageID: assistantMessage.id)
    }

    func generateImage(prompt: String) async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = createUserMessage(content: trimmed)
        var assistantMessage = createEmptyAssistantMessage()
        assistantMessage.messageType = .imageCard
        assistantMessage.content = "正在创建图片"

        let sessionID = sessions[sessionIndex].id
        let previousCount = sessions[sessionIndex].messages.count
        sessions[sessionIndex].messages.append(userMessage)
        sessions[sessionIndex].messages.append(assistantMessage)
        if sessions[sessionIndex].title == "新对话", settings.pluginTitleUpdateMode != .manualOnly {
            sessions[sessionIndex].title = deriveTitle(from: trimmed)
        }
        sessions[sessionIndex].updatedAt = Date().timeIntervalSince1970 * 1000
        generatingSessionID = sessionID
        generatingMessageID = assistantMessage.id
        persistSessions()

        Task { await maybeAutoUpdateTitle(sessionID: sessionID, userContent: trimmed, previousMessageCount: previousCount) }

        do {
            let imageDataURL = try await requestGeneratedImage(prompt: trimmed)
            setGeneratedImage(sessionID: sessionID, messageID: assistantMessage.id, imageDataURL: imageDataURL, prompt: trimmed)
            persistSessions()
        } catch {
            failAssistantMessage(sessionID: sessionID, messageID: assistantMessage.id, errorMessage: error.localizedDescription)
            persistSessions()
        }
    }

    func regenerateLastAssistant() async {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        var lastUser: ChatMessage?
        var messages = sessions[sessionIndex].messages
        while let last = messages.last, last.role == .assistant {
            messages.removeLast()
        }
        lastUser = messages.last(where: { $0.role == .user })
        guard lastUser != nil else { return }
        sessions[sessionIndex].messages = messages
        let expectReasoning = isReasoningModel(settings.model)
        let assistantMessage = createEmptyAssistantMessage(expectReasoning: expectReasoning)
        sessions[sessionIndex].messages.append(assistantMessage)
        sessions[sessionIndex].updatedAt = Date().timeIntervalSince1970 * 1000
        generatingSessionID = sessions[sessionIndex].id
        generatingMessageID = assistantMessage.id
        persistSessions()
        await generateAssistantReply(sessionID: sessions[sessionIndex].id, assistantMessageID: assistantMessage.id)
    }

    func configuredProviders() -> [ProviderMeta] {
        let apiKeys = providerMap(from: settings.providerAPIKeysJSON)
        return providerList.filter { provider in
            let key = (apiKeys[provider.id] ?? fallbackAPIKey(for: provider.id))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return !normalizeAPIKey(key).isEmpty
        }
    }

    func visionPluginModels(for provider: String) -> [String] {
        let modelMap = providerMap(from: settings.providerModelsJSON)
        let models = csvItems(modelMap[provider] ?? defaultModelsCSV(for: provider))
        let capable = models.filter { modelSupportsVision($0) }
        return capable.isEmpty ? models : capable
    }

    func configuredVisionProviders() -> [ProviderMeta] {
        configuredProviders().filter { !visionPluginModels(for: $0.id).isEmpty }
    }

    func modelsByProvider() -> [ProviderMeta: [String]] {
        let apiKeys = providerMap(from: settings.providerAPIKeysJSON)
        let modelMap = providerMap(from: settings.providerModelsJSON)
        var output: [ProviderMeta: [String]] = [:]
        for provider in providerList {
            let key = (apiKeys[provider.id] ?? fallbackAPIKey(for: provider.id)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            output[provider] = csvItems(modelMap[provider.id] ?? defaultModelsCSV(for: provider.id))
        }
        return output
    }

    func favoriteModelsByProvider() -> [ProviderMeta: [String]] {
        let configured = Set(configuredProviders().map(\.id))
        var output: [ProviderMeta: [String]] = [:]
        for provider in providerList where configured.contains(provider.id) {
            let favorites = favoriteModels(for: provider.id).sorted()
            guard !favorites.isEmpty else { continue }
            output[provider] = favorites
        }
        return output
    }

    func appendModels(_ newModels: [String], for provider: String) {
        let incoming = newModels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !incoming.isEmpty else { return }

        var next = settings
        var modelMap = providerMap(from: next.providerModelsJSON)
        var merged = csvItems(modelMap[provider] ?? defaultModelsCSV(for: provider))

        for model in incoming where !merged.contains(model) {
            merged.append(model)
        }

        let mergedCSV = normalizeModelCSV(merged.joined(separator: ","))
        modelMap[provider] = mergedCSV
        next.providerModelsJSON = jsonString(from: modelMap)

        if provider == "openai" {
            next.openAIModelsCSV = mergedCSV
        } else if provider == "deepseek" {
            next.deepSeekModelsCSV = mergedCSV
        }

        updateSettings(next)
    }

    func favoriteModels(for provider: String) -> Set<String> {
        let favorites = providerMap(from: settings.providerFavoritesJSON)
        let fallback = provider == "openai" ? settings.openAIFavoritesCSV : provider == "deepseek" ? settings.deepSeekFavoritesCSV : ""
        return Set(csvItems(favorites[provider] ?? fallback))
    }

    func toggleFavorite(model: String, provider: String) {
        var favorites = providerMap(from: settings.providerFavoritesJSON)
        var current = favoriteModels(for: provider)
        if current.contains(model) {
            current.remove(model)
        } else {
            current.insert(model)
        }
        favorites[provider] = current.sorted().joined(separator: ",")
        settings.providerFavoritesJSON = jsonString(from: favorites)
        storage.saveSettings(settings)
    }

    func allFavoriteModels() -> [(ProviderMeta, String)] {
        providerList.flatMap { provider in
            favoriteModels(for: provider.id).sorted().map { (provider, $0) }
        }
    }

    func applyGPTPreset(_ preset: CustomGPTPreset) {
        var next = settings
        let normalizedProvider = normalizeProviderID(preset.provider)
        let apiKeys = providerMap(from: next.providerAPIKeysJSON)
        let baseURLs = providerMap(from: next.providerBaseURLsJSON)
        next.provider = normalizedProvider
        next.apiKey = apiKeys[normalizedProvider] ?? fallbackAPIKey(for: normalizedProvider)
        next.baseURL = resolvedBaseURL(baseURLs[normalizedProvider], provider: normalizedProvider)
        next.model = preset.model
        next.activeGPTPresetID = preset.id
        next.activeGPTInstructions = preset.instructions
        updateSettings(next)
    }

    func applyModel(provider: String, model: String) {
        let normalizedProvider = normalizeProviderID(provider)
        let apiKeys = providerMap(from: settings.providerAPIKeysJSON)
        let baseURLs = providerMap(from: settings.providerBaseURLsJSON)
        var next = settings
        next.provider = normalizedProvider
        next.apiKey = apiKeys[normalizedProvider] ?? fallbackAPIKey(for: normalizedProvider)
        next.baseURL = resolvedBaseURL(baseURLs[normalizedProvider], provider: normalizedProvider)
        next.model = model
        next.activeGPTPresetID = ""
        next.activeGPTInstructions = ""
        updateSettings(next)
    }

    func speakText(_ text: String, languageCode: String? = nil) async throws {
        try await speech.speak(settings: settings, text: text, languageCode: languageCode)
    }

    func transcribeAudio(fileURL: URL, languageCode: String? = nil) async throws -> String {
        try await speech.transcribe(settings: settings, fileURL: fileURL, languageCode: languageCode)
    }

    private func requestGeneratedImage(prompt: String) async throws -> String {
        let keys = providerMap(from: settings.providerAPIKeysJSON)
        let baseURLs = providerMap(from: settings.providerBaseURLsJSON)
        let provider = "openai"
        let apiKey = normalizeAPIKey(keys[provider] ?? settings.openAIAPIKey)
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ChatStore", code: 40, userInfo: [NSLocalizedDescriptionKey: "请先在设置中配置 OpenAI API Key 后再画图。"])
        }
        return try await api.generateImage(
            apiKey: apiKey,
            baseURL: resolvedBaseURL(baseURLs[provider] ?? settings.openAIBaseURL, provider: provider),
            prompt: prompt
        )
    }

    private func generateAssistantReply(sessionID: String, assistantMessageID: String) async {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        let payload = await buildPayloadMessages(for: session, assistantMessageID: assistantMessageID)
        applySearchMeta(sessionID: sessionID, messageID: assistantMessageID, query: payload.query, date: payload.date, summary: payload.summary, results: payload.results)
        setSearchState(sessionID: sessionID, messageID: assistantMessageID, inProgress: false)

        api.streamChat(settings: settings, messages: payload.messages, callbacks: StreamCallbacks(
            onToken: { [weak self] token in
                self?.appendAssistantToken(sessionID: sessionID, messageID: assistantMessageID, token: token)
            },
            onReasoningToken: { [weak self] token in
                self?.appendAssistantReasoningToken(sessionID: sessionID, messageID: assistantMessageID, token: token)
            },
            onDone: { [weak self] in
                self?.finishAssistantMessage(sessionID: sessionID, messageID: assistantMessageID)
                self?.persistSessions()
            },
            onError: { [weak self] message in
                self?.failAssistantMessage(sessionID: sessionID, messageID: assistantMessageID, errorMessage: message)
                self?.persistSessions()
            }
        ))
    }

    private func buildPayloadMessages(for session: ChatSession, assistantMessageID: String) async -> (messages: [ChatCompletionMessage], query: String, date: String, summary: String, results: [WebSearchResultItem]) {
        let source = session.messages.filter { $0.id != assistantMessageID }
        var systemMessages: [ChatCompletionMessage] = [
            ChatCompletionMessage(role: "system", content: .text(structuredAssistantInstructionPrompt()))
        ]
        let gptInstructions = settings.activeGPTInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !gptInstructions.isEmpty {
            systemMessages.insert(ChatCompletionMessage(role: "system", content: .text(gptInstructions)), at: 0)
        }
        let payloadMessages = systemMessages + source.map(toCompletionMessage)
        guard settings.webSearchEnabled else { return (payloadMessages, "", "", "", []) }
        let lastUser = source.last(where: { $0.role == .user })
        guard lastUser?.webSearchRequested == true else { return (payloadMessages, "", "", "", []) }
        let query = lastUser?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty, query != "[图片]" else { return (payloadMessages, "", "", "", []) }
        print("[WebSearchChain] webSearchRequested=true query=\(query)")
        setSearchState(sessionID: session.id, messageID: assistantMessageID, inProgress: true)
        let searchPayload = await webSearch.searchSummary(query: query, settings: settings)
        let summary = searchPayload.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: Date())
        let normalizedSummary = summary.isEmpty ? "搜索无结果" : summary
        print("[WebSearchChain] searchSummary returned resultCount=\(searchPayload.results.count) summary=\(normalizedSummary)")
        let searchInstruction = """
        你正在回答一个开启了联网搜索的问题。
        请优先基于下面的搜索结果回答；如果搜索无结果，请明确说明“搜索无结果”，再基于已有知识谨慎回答，并标注不确定性。

        你拥有通过 WebSearch 和 WebFetch 工具访问互联网的能力。
        规则：
        - 尽量并行发起彼此独立的搜索和抓取，以提高效率。
        - 当需要多个独立查询或多个独立页面时，优先并行处理，不要串行逐个执行。
        - 不要对相同工具和相同输入重复并行调用。
        """
        let searchEvidence = """
        搜索日期：\(date)
        搜索问题：\(query)

        【联网检索结果】
        \(normalizedSummary)
        """
        let prompt = """
        请优先基于以上联网信息回答，并注明不确定部分。不要说“我无法联网”。
        """
        let injectedMessages = [
            ChatCompletionMessage(role: "system", content: .text(prompt)),
            ChatCompletionMessage(role: "system", content: .text(searchInstruction)),
            ChatCompletionMessage(role: "system", content: .text(searchEvidence))
        ] + payloadMessages
        print("[WebSearchChain] injected search context into messages total=\(injectedMessages.count)")
        return (injectedMessages, query, date, normalizedSummary, searchPayload.results)
    }

    private func toCompletionMessage(_ message: ChatMessage) -> ChatCompletionMessage {
        if message.role == .assistant, let mapCard = message.mapCard {
            let summary = mapCardTranscript(mapCard)
            let fallbackText = summary.isEmpty ? message.content : summary + (message.content.isEmpty ? "" : "\n\n" + message.content)
            return ChatCompletionMessage(role: message.role.rawValue, content: .text(fallbackText))
        }
        if message.role == .user, let image = message.imageDataURL, !image.isEmpty {
            return ChatCompletionMessage(role: "user", content: .parts([
                ChatContentPart(type: "text", text: message.content.isEmpty ? "请识别这张图片内容" : message.content),
                ChatContentPart(type: "image_url", imageURL: ChatImageURL(url: image))
            ]))
        }
        if message.role == .user, let fileName = message.fileName, !fileName.isEmpty {
            let fileExt = message.fileExt ?? ""
            let fileText = message.fileText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let text: String
            if !fileText.isEmpty {
                text = "用户上传了文件《\(fileName)》\(fileExt.isEmpty ? "" : "（.\(fileExt)）")。以下是文件正文（可能截断）：\n\(fileText)\n\n用户问题：\(message.content)"
            } else {
                text = "用户上传了文件《\(fileName)》\(fileExt.isEmpty ? "" : "（.\(fileExt)）")，当前无法直接解析正文。请先告知用户该文件格式暂不支持直接解析，并引导其粘贴关键内容后再分析。\n\n用户问题：\(message.content)"
            }
            return ChatCompletionMessage(role: "user", content: .text(text))
        }
        return ChatCompletionMessage(role: message.role.rawValue, content: .text(message.content))
    }

    private func appendAssistantToken(sessionID: String, messageID: String, token: String) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        sessions[sessionIndex].messages[messageIndex].content += token
        previewStructuredAssistantMessage(sessionIndex: sessionIndex, messageIndex: messageIndex)
        sessions[sessionIndex].messages[messageIndex].generating = true
        sessions[sessionIndex].messages[messageIndex].error = false
        sessions[sessionIndex].updatedAt = Date().timeIntervalSince1970 * 1000
    }

    private func appendAssistantReasoningToken(sessionID: String, messageID: String, token: String) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        if reasoningStartMS[messageID] == nil {
            reasoningStartMS[messageID] = Date().timeIntervalSince1970 * 1000
        }
        sessions[sessionIndex].messages[messageIndex].reasoningContent = (sessions[sessionIndex].messages[messageIndex].reasoningContent ?? "") + token
        sessions[sessionIndex].messages[messageIndex].generating = true
        sessions[sessionIndex].updatedAt = Date().timeIntervalSince1970 * 1000
    }

    private func setGeneratedImage(sessionID: String, messageID: String, imageDataURL: String, prompt: String) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }),
              sessions[sessionIndex].messages[messageIndex].generating == true else { return }
        sessions[sessionIndex].messages[messageIndex].messageType = .imageCard
        sessions[sessionIndex].messages[messageIndex].content = prompt
        sessions[sessionIndex].messages[messageIndex].imageDataURL = imageDataURL
        sessions[sessionIndex].messages[messageIndex].generating = false
        sessions[sessionIndex].messages[messageIndex].error = false
        sessions[sessionIndex].updatedAt = Date().timeIntervalSince1970 * 1000
        generatingSessionID = ""
        generatingMessageID = ""
        hapticTap()
    }

    private func finishAssistantMessage(sessionID: String, messageID: String) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        sessions[sessionIndex].messages[messageIndex].generating = false
        normalizeStructuredAssistantMessage(sessionIndex: sessionIndex, messageIndex: messageIndex)
        finalizeReasoningDuration(messageID: messageID, sessionIndex: sessionIndex, messageIndex: messageIndex)
        sessions[sessionIndex].updatedAt = Date().timeIntervalSince1970 * 1000
        generatingSessionID = ""
        generatingMessageID = ""
        hapticTap()
    }

    private func failAssistantMessage(sessionID: String, messageID: String, errorMessage: String) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        sessions[sessionIndex].messages[messageIndex].generating = false
        sessions[sessionIndex].messages[messageIndex].error = true
        if sessions[sessionIndex].messages[messageIndex].messageType == .imageCard
            || sessions[sessionIndex].messages[messageIndex].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sessions[sessionIndex].messages[messageIndex].content = errorMessage
        }
        finalizeReasoningDuration(messageID: messageID, sessionIndex: sessionIndex, messageIndex: messageIndex)
        generatingSessionID = ""
        generatingMessageID = ""
    }

    private func normalizeStructuredAssistantMessage(sessionIndex: Int, messageIndex: Int) {
        guard sessions.indices.contains(sessionIndex),
              sessions[sessionIndex].messages.indices.contains(messageIndex) else { return }
        guard sessions[sessionIndex].messages[messageIndex].role == .assistant else { return }

        let rawContent = sessions[sessionIndex].messages[messageIndex].content
        if let structuredWeather = parseStructuredWeatherMessage(from: rawContent) {
            sessions[sessionIndex].messages[messageIndex].messageType = .weatherCard
            sessions[sessionIndex].messages[messageIndex].weatherCard = structuredWeather.weatherCard
            sessions[sessionIndex].messages[messageIndex].mapCard = nil
            sessions[sessionIndex].messages[messageIndex].content = structuredWeather.displayText
        } else if let structured = parseStructuredAssistantMessage(from: rawContent) {
            sessions[sessionIndex].messages[messageIndex].messageType = .mapCard
            sessions[sessionIndex].messages[messageIndex].mapCard = structured.mapCard
            sessions[sessionIndex].messages[messageIndex].weatherCard = nil
            sessions[sessionIndex].messages[messageIndex].content = structured.displayText
        } else {
            sessions[sessionIndex].messages[messageIndex].messageType = .text
            sessions[sessionIndex].messages[messageIndex].mapCard = nil
            sessions[sessionIndex].messages[messageIndex].weatherCard = nil
        }
    }

    private func previewStructuredAssistantMessage(sessionIndex: Int, messageIndex: Int) {
        guard sessions.indices.contains(sessionIndex),
              sessions[sessionIndex].messages.indices.contains(messageIndex) else { return }
        guard sessions[sessionIndex].messages[messageIndex].role == .assistant else { return }

        let rawContent = sessions[sessionIndex].messages[messageIndex].content
        if let previewWeather = parseStructuredWeatherPreview(from: rawContent) {
            sessions[sessionIndex].messages[messageIndex].messageType = .weatherCard
            sessions[sessionIndex].messages[messageIndex].weatherCard = previewWeather
            sessions[sessionIndex].messages[messageIndex].mapCard = nil
        } else if let preview = parseStructuredAssistantPreview(from: rawContent) {
            sessions[sessionIndex].messages[messageIndex].messageType = .mapCard
            sessions[sessionIndex].messages[messageIndex].mapCard = preview
            sessions[sessionIndex].messages[messageIndex].weatherCard = nil
        }
    }

    private func applySearchMeta(sessionID: String, messageID: String, query: String, date: String, summary: String, results: [WebSearchResultItem]) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        let resultCount = summary.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }.count
        sessions[sessionIndex].messages[messageIndex].searchQuery = query
        sessions[sessionIndex].messages[messageIndex].searchDate = date
        sessions[sessionIndex].messages[messageIndex].searchSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : summary
        sessions[sessionIndex].messages[messageIndex].searchResultCount = resultCount
        sessions[sessionIndex].messages[messageIndex].searchResults = results.isEmpty ? nil : results
    }

    private func setSearchState(sessionID: String, messageID: String, inProgress: Bool) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }),
              let messageIndex = sessions[sessionIndex].messages.firstIndex(where: { $0.id == messageID }) else { return }
        sessions[sessionIndex].messages[messageIndex].searchInProgress = inProgress
    }

    private func finalizeReasoningDuration(messageID: String, sessionIndex: Int, messageIndex: Int) {
        if let start = reasoningStartMS[messageID] {
            let seconds = max(1, Int(ceil((Date().timeIntervalSince1970 * 1000 - start) / 1000)))
            sessions[sessionIndex].messages[messageIndex].reasoningDurationSec = seconds
        }
        reasoningStartMS[messageID] = nil
    }

    private func persistSessions() {
        sessions.sort { $0.updatedAt > $1.updatedAt }
        storage.saveSessions(sessions)
    }

    private func normalizeSettings(_ settings: AppSettings) -> AppSettings {
        var next = settings
        next.provider = normalizeProviderID(settings.provider)
        next.openAIBaseURL = settings.openAIBaseURL.isEmpty ? defaultBaseURL(for: "openai") : settings.openAIBaseURL
        next.deepSeekBaseURL = settings.deepSeekBaseURL.isEmpty ? defaultBaseURL(for: "deepseek") : settings.deepSeekBaseURL
        next.openAIAPIKey = normalizeAPIKey(settings.openAIAPIKey)
        next.deepSeekAPIKey = normalizeAPIKey(settings.deepSeekAPIKey)
        next.tavilyAPIKey = normalizeAPIKey(settings.tavilyAPIKey)
        next.openAIModelsCSV = normalizeModelCSV(settings.openAIModelsCSV.isEmpty ? defaultModelsCSV(for: "openai") : settings.openAIModelsCSV)
        next.deepSeekModelsCSV = normalizeModelCSV(settings.deepSeekModelsCSV.isEmpty ? defaultModelsCSV(for: "deepseek") : settings.deepSeekModelsCSV)
        let normalizedSearchEngine = settings.webSearchEngine.lowercased()
        next.webSearchEngine = WebSearchEngineOption(rawValue: normalizedSearchEngine)?.rawValue ?? "bing"
        next.webSearchLang = settings.webSearchLang.isEmpty ? "zh-CN" : settings.webSearchLang
        next.webSearchResultLimit = min(15, max(3, settings.webSearchResultLimit))

        var apiKeys = providerMap(from: settings.providerAPIKeysJSON)
        var baseURLs = providerMap(from: settings.providerBaseURLsJSON)
        var models = providerMap(from: settings.providerModelsJSON)
        apiKeys["openai"] = apiKeys["openai"] ?? next.openAIAPIKey
        apiKeys["deepseek"] = apiKeys["deepseek"] ?? next.deepSeekAPIKey
        baseURLs["openai"] = resolvedBaseURL(baseURLs["openai"], provider: "openai")
        baseURLs["deepseek"] = resolvedBaseURL(baseURLs["deepseek"], provider: "deepseek")
        models["openai"] = models["openai"] ?? next.openAIModelsCSV
        models["deepseek"] = models["deepseek"] ?? next.deepSeekModelsCSV
        next.providerAPIKeysJSON = jsonString(from: apiKeys)
        next.providerBaseURLsJSON = jsonString(from: baseURLs)
        next.providerModelsJSON = jsonString(from: models)
        next.apiKey = normalizeAPIKey(settings.apiKey.isEmpty ? (apiKeys[next.provider] ?? fallbackAPIKey(for: next.provider)) : settings.apiKey)
        next.baseURL = settings.baseURL.isEmpty ? resolvedBaseURL(baseURLs[next.provider], provider: next.provider) : settings.baseURL
        next.model = settings.model.isEmpty ? (csvItems(models[next.provider] ?? defaultModelsCSV(for: next.provider)).first ?? "") : settings.model
        next.pluginTitleProvider = normalizeProviderID(settings.pluginTitleProvider.isEmpty ? "deepseek" : settings.pluginTitleProvider)
        next.pluginTitleModel = normalizedPluginModel(
            settings.pluginTitleModel,
            provider: next.pluginTitleProvider,
            fallback: "deepseek-chat",
            models: models
        )
        next.pluginTTSProvider = normalizeSpeechProviderID(settings.pluginTTSProvider.isEmpty ? SpeechServiceProvider.soniox.rawValue : settings.pluginTTSProvider)
        next.pluginTTSAPIKey = normalizeAPIKey(settings.pluginTTSAPIKey)
        next.pluginTTSBaseURL = settings.pluginTTSBaseURL.isEmpty ? defaultSpeechTTSBaseURL(for: next.pluginTTSProvider) : settings.pluginTTSBaseURL
        next.pluginTTSModel = normalizedSpeechPluginValue(
            settings.pluginTTSModel,
            allowed: speechTTSPModels(for: next.pluginTTSProvider),
            fallback: defaultSpeechTTSModel(for: next.pluginTTSProvider)
        )
        next.pluginTTSVoice = normalizedSpeechPluginValue(
            settings.pluginTTSVoice,
            allowed: speechTTSVoiceOptions(for: next.pluginTTSProvider).map(\.id),
            fallback: defaultSpeechTTSVoice(for: next.pluginTTSProvider)
        )
        next.pluginSTTProvider = normalizeSpeechProviderID(settings.pluginSTTProvider.isEmpty ? SpeechServiceProvider.soniox.rawValue : settings.pluginSTTProvider)
        next.pluginSTTAPIKey = normalizeAPIKey(settings.pluginSTTAPIKey)
        next.pluginSTTBaseURL = settings.pluginSTTBaseURL.isEmpty ? defaultSpeechSTTBaseURL(for: next.pluginSTTProvider) : settings.pluginSTTBaseURL
        next.pluginSTTModel = normalizedSpeechPluginValue(
            settings.pluginSTTModel,
            allowed: speechSTTModels(for: next.pluginSTTProvider),
            fallback: defaultSpeechSTTModel(for: next.pluginSTTProvider)
        )
        let sourceLanguageCode = settings.translationSourceLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetLanguageCode = settings.translationTargetLanguageCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        next.translationSourceLanguageCode = translationLanguageOptions.contains(where: { $0.code == sourceLanguageCode }) ? sourceLanguageCode : "auto"
        next.translationTargetLanguageCode = translationLanguageOptions.contains(where: { $0.code == targetLanguageCode && $0.code != "auto" }) ? targetLanguageCode : "en"
        next.pluginVisionProvider = normalizeProviderID(settings.pluginVisionProvider.isEmpty ? "openai" : settings.pluginVisionProvider)
        next.pluginVisionModel = normalizedPluginModel(
            settings.pluginVisionModel,
            provider: next.pluginVisionProvider,
            fallback: "gpt-4.1-mini",
            models: models
        )
        next.pluginMapProvider = MapProviderOption(rawValue: settings.pluginMapProvider.lowercased())?.rawValue ?? MapProviderOption.yandex.rawValue
        next.pluginMapAPIKey = normalizeAPIKey(settings.pluginMapAPIKey)
        next.customComposerPlaceholder = settings.customComposerPlaceholder.trimmingCharacters(in: .whitespacesAndNewlines)
        next.showMessageTimestamps = settings.showMessageTimestamps
        next.sendWithCommandReturn = settings.sendWithCommandReturn
        next.defaultWebSearchEnabled = settings.defaultWebSearchEnabled
        next.activeGPTPresetID = settings.activeGPTPresetID
        return next
    }

    private func fallbackAPIKey(for provider: String) -> String {
        switch provider {
        case "openai": return settings.openAIAPIKey
        case "deepseek": return settings.deepSeekAPIKey
        default: return ""
        }
    }

    private func fallbackBaseURL(for provider: String) -> String {
        switch provider {
        case "openai": return settings.openAIBaseURL
        case "deepseek": return settings.deepSeekBaseURL
        default: return defaultBaseURL(for: provider)
        }
    }

    private func resolvedBaseURL(_ value: String?, provider: String) -> String {
        let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? fallbackBaseURL(for: provider) : normalized
    }

    private func isReasoningModel(_ model: String) -> Bool {
        let normalized = model.lowercased()
        return normalized.contains("reasoner") || normalized.contains("reasoning") || normalized.contains("thinking")
    }

    private func normalizedPluginModel(_ value: String, provider: String, fallback: String, models: [String: String]) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return csvItems(models[provider] ?? defaultModelsCSV(for: provider)).first ?? fallback
    }

    private func normalizedSpeechPluginValue(_ value: String, allowed: [String], fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if allowed.contains(trimmed) {
            return trimmed
        }
        return fallback
    }

    private func visionAssistIfNeeded(imageDataURL: String, userText: String) async -> (imageDataURL: String, userText: String) {
        guard !imageDataURL.isEmpty else { return (imageDataURL, userText) }
        if modelSupportsVision(settings.model) { return (imageDataURL, userText) }
        guard hasVisionPluginConfigured else { return (imageDataURL, userText) }

        do {
            let description = try await describeImage(imageDataURL)
            let augmented = userText.isEmpty ? description : "\(userText)\n\n[图片描述]\n\(description)"
            return ("", augmented)
        } catch {
            let notice = "[图片描述不可用：请在设置 → 插件 → 辅助视觉模型中配置支持识图的模型]"
            let augmented = userText.isEmpty ? notice : "\(userText)\n\n\(notice)"
            return ("", augmented)
        }
    }

    private func describeImage(_ imageDataURL: String) async throws -> String {
        let keys = providerMap(from: settings.providerAPIKeysJSON)
        let baseURLs = providerMap(from: settings.providerBaseURLsJSON)
        let provider = settings.pluginVisionProvider
        let apiKey = normalizeAPIKey(keys[provider] ?? fallbackAPIKey(for: provider))
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ChatStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "辅助视觉模型未配置 API Key"])
        }
        guard modelSupportsVision(settings.pluginVisionModel) else {
            throw NSError(domain: "ChatStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "所选模型不支持识图"])
        }

        let baseURL = resolvedBaseURL(baseURLs[provider], provider: provider)
        let model = settings.pluginVisionModel

        let messages = [
            ChatCompletionMessage(role: "system", content: .text("Describe this image accurately in the user's language. Output plain text only.")),
            ChatCompletionMessage(role: "user", content: .parts([
                ChatContentPart(type: "text", text: "请详细描述这张图片。"),
                ChatContentPart(type: "image_url", imageURL: ChatImageURL(url: imageDataURL))
            ]))
        ]

        let description = try await api.completeChat(provider: provider, model: model, apiKey: apiKey, baseURL: baseURL, messages: messages)
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "ChatStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "视觉模型未返回描述"])
        }
        return trimmed
    }

    private var hasVisionPluginConfigured: Bool {
        let keys = providerMap(from: settings.providerAPIKeysJSON)
        let provider = settings.pluginVisionProvider
        let apiKey = keys[provider] ?? fallbackAPIKey(for: provider)
        return !normalizeAPIKey(apiKey).isEmpty
            && !settings.pluginVisionModel.isEmpty
            && modelSupportsVision(settings.pluginVisionModel)
    }

    private func maybeAutoUpdateTitle(sessionID: String, userContent: String, previousMessageCount: Int) async {
        let mode = settings.pluginTitleUpdateMode
        if mode == .manualOnly { return }
        if mode == .firstMessage && previousMessageCount > 0 { return }

        let source = userContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty, source != "[图片]" else { return }
        guard hasTitlePluginConfigured else { return }
        await generateTitle(sessionID: sessionID, from: source)
    }

    private var hasTitlePluginConfigured: Bool {
        let keys = providerMap(from: settings.providerAPIKeysJSON)
        let provider = settings.pluginTitleProvider
        let apiKey = keys[provider] ?? fallbackAPIKey(for: provider)
        return !normalizeAPIKey(apiKey).isEmpty && !settings.pluginTitleModel.isEmpty
    }

    private func generateTitle(sessionID: String, from content: String) async {
        guard sessions.contains(where: { $0.id == sessionID }) else { return }

        let keys = providerMap(from: settings.providerAPIKeysJSON)
        let baseURLs = providerMap(from: settings.providerBaseURLsJSON)
        let provider = settings.pluginTitleProvider
        let apiKey = keys[provider] ?? fallbackAPIKey(for: provider)
        let normalizedKey = normalizeAPIKey(apiKey)
        guard !normalizedKey.isEmpty else { return }

        let baseURL = resolvedBaseURL(baseURLs[provider], provider: provider)
        let model = settings.pluginTitleModel

        let messages = [
            ChatCompletionMessage(role: "system", content: .text("Generate a concise chat title within 24 characters. Use the same language as the user message. Output only the title without quotes.")),
            ChatCompletionMessage(role: "user", content: .text(content))
        ]

        do {
            let raw = try await api.completeChat(provider: provider, model: model, apiKey: normalizedKey, baseURL: baseURL, messages: messages)
            let title = deriveTitle(from: raw.trimmingCharacters(in: .whitespacesAndNewlines))
            guard title != "新对话" else { return }
            renameSession(sessionID, title: title)
        } catch {
            let fallback = deriveTitle(from: content)
            guard fallback != "新对话" else { return }
            renameSession(sessionID, title: fallback)
        }
    }
}
