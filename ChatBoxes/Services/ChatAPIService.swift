import Foundation

struct StreamCallbacks {
    var onToken: @MainActor (String) -> Void
    var onReasoningToken: @MainActor (String) -> Void
    var onDone: @MainActor () -> Void
    var onError: @MainActor (String) -> Void
}

final class ChatAPIService {
    static let shared = ChatAPIService()

    private var streamTask: Task<Void, Never>?

    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }

    func streamChat(settings: AppSettings, messages: [ChatCompletionMessage], callbacks: StreamCallbacks) {
        stop()
        streamTask = Task {
            do {
                try await streamChatInternal(settings: settings, messages: messages, callbacks: callbacks)
            } catch is CancellationError {
                callbacks.onDone()
            } catch {
                callbacks.onError(mapRuntimeError(error))
            }
        }
    }

    func fetchModels(baseURL: String, apiKey: String) async throws -> [String] {
        let normalized = baseURL.replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        let urlString: String
        if normalized.hasSuffix("/v1/models") || normalized.hasSuffix("/models") {
            urlString = normalized
        } else if normalized.hasSuffix("/v1") {
            urlString = "\(normalized)/models"
        } else {
            urlString = "\(normalized)/v1/models"
        }

        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(normalizeAPIKey(apiKey))", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "ChatAPIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "获取模型列表失败"])
        }

        let body = String(data: data, encoding: .utf8) ?? ""
        guard 200..<300 ~= http.statusCode else {
            throw NSError(domain: "ChatAPIService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "获取模型列表失败（\(http.statusCode)）" : body])
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let items = json["data"] as? [[String: Any]] {
                let models = items.compactMap { $0["id"] as? String }.sorted()
                if !models.isEmpty { return models }
            }
            if let items = json["models"] as? [[String: Any]] {
                let models = items.compactMap { $0["id"] as? String }.sorted()
                if !models.isEmpty { return models }
            }
            if let items = json["data"] as? [String] {
                let models = items.sorted()
                if !models.isEmpty { return models }
            }
        }

        throw NSError(
            domain: "ChatAPIService",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: body.isEmpty ? "模型列表返回格式无法识别。" : "模型列表返回格式无法识别：\(body.prefix(240))"]
        )
    }

    private func streamChatInternal(settings: AppSettings, messages: [ChatCompletionMessage], callbacks: StreamCallbacks) async throws {
        let validationError = validate(settings)
        if !validationError.isEmpty {
            callbacks.onError(validationError)
            return
        }

        let request = try buildRequest(settings: settings, messages: messages, stream: true)
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "ChatAPIService", code: 2, userInfo: [NSLocalizedDescriptionKey: "无效响应"])
            }
            guard 200..<300 ~= http.statusCode else {
                throw NSError(
                    domain: "ChatAPIService",
                    code: http.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: mapHTTPError(statusCode: http.statusCode, body: "")]
                )
            }

            var emitted = false
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard line.hasPrefix("data:") else { continue }
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !payload.isEmpty, payload != "[DONE]",
                      let data = payload.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if let token = extractContentToken(json), !token.isEmpty {
                    emitted = true
                    callbacks.onToken(token)
                }
                if let token = extractReasoningToken(json), !token.isEmpty {
                    callbacks.onReasoningToken(token)
                }
            }

            if !emitted {
                let response = try await requestChatOnce(settings: settings, messages: messages)
                if !response.reasoning.isEmpty {
                    callbacks.onReasoningToken(response.reasoning)
                }
                if !response.content.isEmpty {
                    callbacks.onToken(response.content)
                }
            }
            callbacks.onDone()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let response = try await requestChatOnce(settings: settings, messages: messages)
            if !response.reasoning.isEmpty {
                callbacks.onReasoningToken(response.reasoning)
            }
            if !response.content.isEmpty {
                callbacks.onToken(response.content)
            }
            callbacks.onDone()
        }
    }

    private func requestChatOnce(settings: AppSettings, messages: [ChatCompletionMessage]) async throws -> (content: String, reasoning: String) {
        let request = try buildRequest(settings: settings, messages: messages, stream: false)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "ChatAPIService", code: 3, userInfo: [NSLocalizedDescriptionKey: mapHTTPError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (String(data: data, encoding: .utf8) ?? "", "")
        }
        return (extractContentToken(json) ?? "", extractReasoningToken(json) ?? "")
    }

    func completeChat(settings: AppSettings, messages: [ChatCompletionMessage]) async throws -> String {
        let response = try await requestChatOnce(settings: settings, messages: messages)
        return response.content
    }

    func completeChat(provider: String, model: String, apiKey: String, baseURL: String, messages: [ChatCompletionMessage]) async throws -> String {
        var temp = AppSettings()
        temp.provider = provider
        temp.model = model
        temp.apiKey = apiKey
        temp.baseURL = baseURL
        return try await completeChat(settings: temp, messages: messages)
    }

    func generateImage(apiKey: String, baseURL: String, prompt: String, model: String = "gpt-image-1", size: String = "1024x1024", quality: String = "medium") async throws -> String {
        let normalized = baseURL.replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        let urlString: String
        if normalized.hasSuffix("/images/generations") {
            urlString = normalized
        } else if normalized.hasSuffix("/v1") {
            urlString = "\(normalized)/images/generations"
        } else {
            urlString = "\(normalized)/v1/images/generations"
        }

        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(normalizeAPIKey(apiKey))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "prompt": prompt,
            "size": size,
            "quality": quality,
            "n": 1
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "ChatAPIService", code: 30, userInfo: [NSLocalizedDescriptionKey: mapHTTPError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: String(data: data, encoding: .utf8) ?? "")])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]],
              let first = items.first else {
            throw NSError(domain: "ChatAPIService", code: 31, userInfo: [NSLocalizedDescriptionKey: "图片接口返回格式无法识别"])
        }
        if let b64 = first["b64_json"] as? String, !b64.isEmpty {
            return "data:image/png;base64,\(b64)"
        }
        if let urlText = first["url"] as? String, let url = URL(string: urlText) {
            let (imageData, _) = try await URLSession.shared.data(from: url)
            return "data:image/png;base64,\(imageData.base64EncodedString())"
        }
        throw NSError(domain: "ChatAPIService", code: 32, userInfo: [NSLocalizedDescriptionKey: "图片接口没有返回图片数据"])
    }

    private func buildRequest(settings: AppSettings, messages: [ChatCompletionMessage], stream: Bool) throws -> URLRequest {
        let normalized = settings.baseURL.replacingOccurrences(of: "/$", with: "", options: .regularExpression)
        let urlString: String
        if normalized.hasSuffix("/v1/chat/completions") || normalized.hasSuffix("/chat/completions") {
            urlString = normalized
        } else if normalized.hasSuffix("/v1") {
            urlString = "\(normalized)/chat/completions"
        } else {
            urlString = "\(normalized)/v1/chat/completions"
        }
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(normalizeAPIKey(settings.apiKey))", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": settings.model,
            "messages": messages.map(encodedMessage),
            "stream": stream
        ])
        return request
    }

    private func encodedMessage(_ message: ChatCompletionMessage) -> [String: Any] {
        let apiRole = normalizedAPIRole(message.role)
        switch message.content {
        case .text(let text):
            return ["role": apiRole, "content": text]
        case .parts(let parts):
            return [
                "role": apiRole,
                "content": parts.map { part in
                    var item: [String: Any] = ["type": part.type]
                    if let text = part.text { item["text"] = text }
                    if let imageURL = part.imageURL { item["image_url"] = ["url": imageURL.url] }
                    return item
                }
            ]
        }
    }

    private func normalizedAPIRole(_ role: String) -> String {
        role == "developer" ? "system" : role
    }

    private func extractContentToken(_ json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        if let delta = first["delta"] as? [String: Any], let content = delta["content"] as? String {
            return content
        }
        if let message = first["message"] as? [String: Any], let content = message["content"] as? String {
            return content
        }
        return nil
    }

    private func extractReasoningToken(_ json: [String: Any]) -> String? {
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else { return nil }
        if let delta = first["delta"] as? [String: Any] {
            return (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String)
        }
        if let message = first["message"] as? [String: Any] {
            return (message["reasoning_content"] as? String) ?? (message["reasoning"] as? String)
        }
        return nil
    }

    private func validate(_ settings: AppSettings) -> String {
        if normalizeAPIKey(settings.apiKey).isEmpty { return "请先在设置中填写 API Key。" }
        if settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请先在设置中填写 Base URL。" }
        if settings.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请先在设置中填写模型名称。" }
        return ""
    }

    private func mapHTTPError(statusCode: Int, body: String) -> String {
        body.isEmpty ? "请求失败（\(statusCode)）" : "请求失败（\(statusCode)）：\(body)"
    }

    private func mapRuntimeError(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.code == NSURLErrorNotConnectedToInternet {
            return "网络不可用，请检查连接。"
        }
        return nsError.localizedDescription
    }
}
