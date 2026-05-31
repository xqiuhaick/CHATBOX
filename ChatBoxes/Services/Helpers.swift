import AppKit
import AVFoundation
import Foundation
import Speech

private let appSettingsKey = "chatbox.settings"

struct StructuredMapCardEnvelope: Equatable {
    let mapCard: MapCardPayload
    let displayText: String
}

struct StructuredWeatherCardEnvelope: Equatable {
    let weatherCard: WeatherCardPayload
    let displayText: String
}

func mapCardTranscript(_ mapCard: MapCardPayload) -> String {
    [
        "地图卡片：\(mapCard.title)",
        mapCard.subtitle,
        mapCard.address,
        mapCard.openingHours.map { "营业时间：\($0)" },
        mapCard.website.map { "网站：\($0)" },
        mapCard.phone.map { "电话：\($0)" },
        "坐标：\(mapCard.coordinateText)"
    ]
    .compactMap { value in
        guard let value, !value.isEmpty else { return nil }
        return value
    }
    .joined(separator: "\n")
}

func weatherCardTranscript(_ weatherCard: WeatherCardPayload) -> String {
    let daily = weatherCard.dailyForecasts.map { item in
        "\(item.day)：\(Int(item.highC.rounded()))°/\(Int(item.lowC.rounded()))°"
    }.joined(separator: "；")

    return [
        "天气卡片：\(weatherCard.location)",
        "当前温度：\(Int(weatherCard.currentTempC.rounded()))°C",
        "天气：\(weatherCard.condition)",
        daily.isEmpty ? nil : "未来天气：\(daily)",
        weatherCard.source.map { "来源：\($0)" }
    ]
    .compactMap { value in
        guard let value, !value.isEmpty else { return nil }
        return value
    }
    .joined(separator: "\n")
}

func generateID(prefix: String) -> String {
    "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 0...99999))"
}

func reasoningDurationTitle(seconds: Int?) -> String {
    guard let seconds, seconds >= 20 else { return "已思考若干秒" }
    return "已思考 \(seconds) 秒"
}

func createEmptyAssistantMessage(expectReasoning: Bool = false) -> ChatMessage {
    ChatMessage(
        id: generateID(prefix: "msg"),
        role: .assistant,
        content: "",
        messageType: .text,
        mapCard: nil,
        weatherCard: nil,
        reasoningContent: "",
        reasoningDurationSec: nil,
        expectReasoning: expectReasoning,
        searchInProgress: false,
        searchResultCount: nil,
        createdAt: Date().timeIntervalSince1970 * 1000,
        imageDataURL: nil,
        generating: true,
        error: false
    )
}

func createUserMessage(content: String) -> ChatMessage {
    ChatMessage(id: generateID(prefix: "msg"), role: .user, content: content, messageType: .text, weatherCard: nil, createdAt: Date().timeIntervalSince1970 * 1000)
}

func createUserMessageWithImage(content: String, imageDataURL: String) -> ChatMessage {
    ChatMessage(id: generateID(prefix: "msg"), role: .user, content: content, messageType: .text, weatherCard: nil, createdAt: Date().timeIntervalSince1970 * 1000, imageDataURL: imageDataURL)
}

func createUserMessageWithFile(content: String, fileName: String, fileExt: String, fileText: String) -> ChatMessage {
    ChatMessage(id: generateID(prefix: "msg"), role: .user, content: content, messageType: .text, weatherCard: nil, fileName: fileName, fileExt: fileExt, fileText: fileText, createdAt: Date().timeIntervalSince1970 * 1000)
}

func createSession(title: String = "新对话") -> ChatSession {
    let now = Date().timeIntervalSince1970 * 1000
    return ChatSession(id: generateID(prefix: "session"), title: title, createdAt: now, updatedAt: now, messages: [])
}

func deriveTitle(from content: String) -> String {
    let normalized = content.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return "新对话" }
    return normalized.count > 24 ? String(normalized.prefix(24)) + "..." : normalized
}

func modelSupportsVision(_ model: String) -> Bool {
    let normalized = model.lowercased()
    return normalized.contains("vision")
        || normalized.contains("gpt-4")
        || normalized.contains("gpt-5")
        || normalized.contains("gemini")
        || normalized.contains("claude-3")
        || normalized.contains("claude-sonnet")
        || normalized.contains("claude-opus")
        || normalized.contains("qwen-vl")
        || normalized.contains("glm-4v")
}

func normalizeAPIKey(_ value: String) -> String {
    var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.hasPrefix("Bearer ") {
        normalized.removeFirst(7)
    }
    normalized = normalized.replacingOccurrences(of: "\"", with: "")
    normalized = normalized.replacingOccurrences(of: "'", with: "")
    normalized = normalized.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    return normalized
}

func normalizeModelCSV(_ value: String) -> String {
    var seen = Set<String>()
    return value
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty && seen.insert($0).inserted }
        .joined(separator: ",")
}

func csvItems(_ csv: String) -> [String] {
    normalizeModelCSV(csv).split(separator: ",").map(String.init)
}

func hapticTap() {
    guard let data = UserDefaults.standard.data(forKey: appSettingsKey),
          let settings = try? JSONDecoder().decode(AppSettings.self, from: data),
          settings.hapticsEnabled else { return }
    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

func translationLanguageOption(for code: String) -> TranslationLanguageOption {
    let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return translationLanguageOptions.first(where: { $0.code == normalized })
        ?? translationLanguageOptions.first(where: { $0.code == "en" })!
}

struct ChatBoxSpeechRecordingCapture {
    let url: URL
    let duration: TimeInterval
}

@MainActor
final class ChatBoxSpeechTranslationService: NSObject, AVAudioPlayerDelegate {
    static let shared = ChatBoxSpeechTranslationService()

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var playbackURL: URL?
    private var playbackContinuation: CheckedContinuation<Void, Error>?
    private var currentRecordingURL: URL?
    private var avSpeechSynthesizer: AVSpeechSynthesizer?
    private var avSpeechDelegate: AVSpeechSynthesisDelegateHandler?

    func requestMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        @unknown default:
            return false
        }
    }

    func startRecording() throws {
        stopPlayback()
        try configureSession()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatbox-translation-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.prepareToRecord()

        guard recorder?.record() == true else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法开始录音"])
        }

        currentRecordingURL = url
    }

    func stopRecording() -> ChatBoxSpeechRecordingCapture? {
        guard let recorder, let currentRecordingURL else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.currentRecordingURL = nil
        return ChatBoxSpeechRecordingCapture(url: currentRecordingURL, duration: duration)
    }

    func cancelRecording() {
        recorder?.stop()
        recorder = nil
        if let currentRecordingURL {
            try? FileManager.default.removeItem(at: currentRecordingURL)
        }
        self.currentRecordingURL = nil
    }

    func play(data: Data, fileExtension: String? = nil) async throws {
        stopPlayback()
        try configureSession()

        let resolvedExtension = normalizedAudioFileExtension(fileExtension, data: data)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chatbox-playback-\(UUID().uuidString).\(resolvedExtension)")
        try data.write(to: url, options: .atomic)

        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()

        guard player.play() else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 2, userInfo: [NSLocalizedDescriptionKey: "音频播放失败"])
        }

        self.player = player
        self.playbackURL = url

        try await withCheckedThrowingContinuation { continuation in
            self.playbackContinuation = continuation
        }
    }

    func stopPlayback() {
        let continuation = playbackContinuation
        playbackContinuation = nil
        avSpeechSynthesizer?.stopSpeaking(at: .immediate)
        avSpeechSynthesizer = nil
        avSpeechDelegate = nil
        player?.stop()
        player = nil
        if let playbackURL {
            try? FileManager.default.removeItem(at: playbackURL)
        }
        playbackURL = nil
        continuation?.resume(
            throwing: NSError(domain: "ChatBoxSpeechTranslationService", code: 3, userInfo: [NSLocalizedDescriptionKey: "播放已中断"])
        )
    }

    func speak(settings: AppSettings, text: String, languageCode: String? = nil) async throws {
        if normalizeSpeechProviderID(settings.pluginTTSProvider) == SpeechServiceProvider.system.rawValue {
            try await speakWithSystem(text: text, voiceIdentifier: settings.pluginTTSVoice)
            return
        }
        let audio = try await synthesizeSpeech(settings: settings, text: text, languageCode: languageCode)
        try await play(data: audio.data, fileExtension: audio.fileExtension)
    }

    func requestSpeechRecognitionPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(settings: AppSettings, fileURL: URL, languageCode: String? = nil) async throws -> String {
        switch normalizeSpeechProviderID(settings.pluginSTTProvider) {
        case SpeechServiceProvider.openai.rawValue:
            return try await transcribeWithOpenAI(settings: settings, fileURL: fileURL, languageCode: languageCode)
        case SpeechServiceProvider.elevenlabs.rawValue:
            return try await transcribeWithElevenLabs(settings: settings, fileURL: fileURL, languageCode: languageCode)
        case SpeechServiceProvider.system.rawValue:
            return try await transcribeWithSystem(fileURL: fileURL, languageCode: languageCode, localeID: settings.pluginSTTModel)
        default:
            return try await transcribeWithSoniox(settings: settings, fileURL: fileURL, languageCode: languageCode)
        }
    }

    private func synthesizeSpeech(settings: AppSettings, text: String, languageCode: String?) async throws -> AudioPlaybackPayload {
        switch normalizeSpeechProviderID(settings.pluginTTSProvider) {
        case SpeechServiceProvider.openai.rawValue:
            return try await synthesizeWithOpenAI(settings: settings, text: text)
        case SpeechServiceProvider.elevenlabs.rawValue:
            return try await synthesizeWithElevenLabs(settings: settings, text: text)
        default:
            return try await synthesizeWithSoniox(
                settings: settings,
                text: text,
                languageCode: languageCode ?? settings.translationTargetLanguageCode
            )
        }
    }

    @MainActor
    private func speakWithSystem(text: String, voiceIdentifier: String) async throws {
        let trimmed = normalizeSpeechText(text)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 24, userInfo: [NSLocalizedDescriptionKey: "没有可朗读的文本"])
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let handler = AVSpeechSynthesisDelegateHandler(continuation: continuation)
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = handler
            handler.synthesizer = synthesizer
            avSpeechDelegate = handler
            avSpeechSynthesizer = synthesizer

            let utterance = AVSpeechUtterance(string: trimmed)
            if !voiceIdentifier.isEmpty,
               let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
                utterance.voice = voice
            }
            synthesizer.speak(utterance)
        }
        avSpeechDelegate = nil
        avSpeechSynthesizer = nil
    }

    private func transcribeWithSystem(fileURL: URL, languageCode: String?, localeID: String) async throws -> String {
        guard await requestSpeechRecognitionPermission() else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 15, userInfo: [NSLocalizedDescriptionKey: "需要语音识别权限，请在系统设置中允许本应用使用语音识别"])
        }

        let locale = speechRecognitionLocale(languageCode: languageCode, localeID: localeID)
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 16, userInfo: [NSLocalizedDescriptionKey: "当前系统语音识别不可用，请更换语言后重试"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = SFSpeechURLRecognitionRequest(url: fileURL)
            request.shouldReportPartialResults = false
            var finished = false

            recognizer.recognitionTask(with: request) { result, error in
                if finished { return }
                if let error {
                    finished = true
                    continuation.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                finished = true
                let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty {
                    continuation.resume(throwing: NSError(
                        domain: "ChatBoxSpeechTranslationService",
                        code: 17,
                        userInfo: [NSLocalizedDescriptionKey: "没有识别到可用文本"]
                    ))
                } else {
                    continuation.resume(returning: text)
                }
            }
        }
    }

    private func transcribeWithElevenLabs(settings: AppSettings, fileURL: URL, languageCode: String?) async throws -> String {
        let apiKey = resolvedAPIKey(settings.pluginSTTAPIKey, fallback: "")
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 18, userInfo: [NSLocalizedDescriptionKey: "请先在设置中填写 ElevenLabs API Key"])
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let requestURL = try makeCompatibleURL(base: settings.pluginSTTBaseURL, path: "/speech-to-text")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeElevenLabsSTTBody(
            fileURL: fileURL,
            boundary: boundary,
            modelID: settings.pluginSTTModel
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(data: data, response: response, prefix: "ElevenLabs 语音识别失败")
        if let decoded = try? JSONDecoder().decode(ElevenLabsSTTResponse.self, from: data) {
            let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = json["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        throw NSError(domain: "ChatBoxSpeechTranslationService", code: 19, userInfo: [NSLocalizedDescriptionKey: "ElevenLabs 未返回可用文本"])
    }

    private func synthesizeWithElevenLabs(settings: AppSettings, text: String) async throws -> AudioPlaybackPayload {
        let apiKey = resolvedAPIKey(settings.pluginTTSAPIKey, fallback: "")
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 26, userInfo: [NSLocalizedDescriptionKey: "请先在设置中填写 ElevenLabs API Key"])
        }

        let voiceID = settings.pluginTTSVoice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !voiceID.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 27, userInfo: [NSLocalizedDescriptionKey: "请先选择 ElevenLabs 声音"])
        }

        let requestURL = try makeCompatibleURL(base: settings.pluginTTSBaseURL, path: "/text-to-speech/\(voiceID)")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(
            ElevenLabsTTSPayload(
                text: normalizeSpeechText(text),
                modelID: settings.pluginTTSModel
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(data: data, response: response, prefix: "ElevenLabs 语音合成失败")
        guard !data.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 28, userInfo: [NSLocalizedDescriptionKey: "ElevenLabs 没有返回可播放音频"])
        }
        return AudioPlaybackPayload(
            data: data,
            fileExtension: audioFileExtension(from: response, fallbackData: data)
        )
    }

    private func speechRecognitionLocale(languageCode: String?, localeID: String) -> Locale {
        let trimmedLocale = localeID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLocale.isEmpty, Locale(identifier: trimmedLocale).identifier != "en_US_POSIX" {
            return Locale(identifier: trimmedLocale)
        }
        if let languageCode, let code = normalizedLanguageCode(languageCode) {
            return Locale(identifier: code)
        }
        return Locale(identifier: "zh-CN")
    }

    private func makeElevenLabsSTTBody(fileURL: URL, boundary: String, modelID: String) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        let mime = fileURL.pathExtension.lowercased() == "wav" ? "audio/wav" : "audio/m4a"
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"model_id\"\r\n\r\n")
        append("\(modelID)\r\n")

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(fileData)
        append("\r\n")
        append("--\(boundary)--\r\n")
        return body
    }

    private func transcribeWithOpenAI(settings: AppSettings, fileURL: URL, languageCode: String?) async throws -> String {
        let apiKey = resolvedAPIKey(settings.pluginSTTAPIKey, fallback: settings.openAIAPIKey)
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 10, userInfo: [NSLocalizedDescriptionKey: "请先在设置中填写语音转文本 API Key"])
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let requestURL = try makeCompatibleURL(base: settings.pluginSTTBaseURL, path: "/audio/transcriptions")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeMultipartBody(
            fileURL: fileURL,
            boundary: boundary,
            model: settings.pluginSTTModel,
            languageCode: normalizedLanguageCode(languageCode)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(data: data, response: response, prefix: "语音识别失败")
        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 11, userInfo: [NSLocalizedDescriptionKey: "没有识别到可用文本"])
        }
        return text
    }

    private func transcribeWithSoniox(settings: AppSettings, fileURL: URL, languageCode: String?) async throws -> String {
        let apiKey = resolvedAPIKey(settings.pluginSTTAPIKey, fallback: "")
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 12, userInfo: [NSLocalizedDescriptionKey: "请先在设置中填写 Soniox 语音识别 API Key"])
        }

        let fileID = try await uploadAudioFileToSoniox(fileURL: fileURL, baseURL: settings.pluginSTTBaseURL, apiKey: apiKey)
        var transcriptionID: String?

        defer {
            let fileIDSnapshot = fileID
            let transcriptionIDSnapshot = transcriptionID
            Task {
                if let transcriptionIDSnapshot {
                    try? await deleteSonioxTranscription(id: transcriptionIDSnapshot, baseURL: settings.pluginSTTBaseURL, apiKey: apiKey)
                }
                try? await deleteSonioxFile(id: fileIDSnapshot, baseURL: settings.pluginSTTBaseURL, apiKey: apiKey)
            }
        }

        transcriptionID = try await createSonioxTranscription(
            fileID: fileID,
            baseURL: settings.pluginSTTBaseURL,
            apiKey: apiKey,
            model: sonioxTranscriptionModel(for: settings.pluginSTTModel),
            languageHints: normalizedLanguageCode(languageCode).map { [$0] } ?? []
        )

        guard let transcriptionID else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 13, userInfo: [NSLocalizedDescriptionKey: "Soniox 转写任务创建失败"])
        }

        try await waitForSonioxTranscription(id: transcriptionID, baseURL: settings.pluginSTTBaseURL, apiKey: apiKey)
        let transcript = try await fetchSonioxTranscript(id: transcriptionID, baseURL: settings.pluginSTTBaseURL, apiKey: apiKey)
        let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 14, userInfo: [NSLocalizedDescriptionKey: "Soniox 未返回可用文本"])
        }
        return text
    }

    private func synthesizeWithOpenAI(settings: AppSettings, text: String) async throws -> AudioPlaybackPayload {
        let apiKey = resolvedAPIKey(settings.pluginTTSAPIKey, fallback: settings.openAIAPIKey)
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 20, userInfo: [NSLocalizedDescriptionKey: "请先在设置中填写文本转语音 API Key"])
        }

        let requestURL = try makeCompatibleURL(base: settings.pluginTTSBaseURL, path: "/audio/speech")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg, audio/*;q=0.9, application/json;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            OpenAITTSPayload(
                model: settings.pluginTTSModel,
                voice: settings.pluginTTSVoice,
                input: normalizeSpeechText(text),
                instructions: settings.pluginTTSPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : settings.pluginTTSPrompt,
                responseFormat: "mp3"
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(data: data, response: response, prefix: "语音合成失败")
        let audio = try extractCompatibleProviderAudioData(data: data, response: response)
        guard !audio.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 21, userInfo: [NSLocalizedDescriptionKey: "语音接口没有返回可播放音频"])
        }
        return AudioPlaybackPayload(
            data: audio,
            fileExtension: audioFileExtension(from: response, fallbackData: audio)
        )
    }

    private func synthesizeWithSoniox(settings: AppSettings, text: String, languageCode: String) async throws -> AudioPlaybackPayload {
        let apiKey = resolvedAPIKey(settings.pluginTTSAPIKey, fallback: "")
        guard !apiKey.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 22, userInfo: [NSLocalizedDescriptionKey: "请先在设置中填写 Soniox 文本转语音 API Key"])
        }

        let requestURL = try makeDirectURL(base: settings.pluginTTSBaseURL, path: "/tts")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg, audio/mp3, audio/wav, audio/*;q=0.9, application/json;q=0.1", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            SonioxTTSPayload(
                model: settings.pluginTTSModel,
                language: normalizedLanguageCode(languageCode) ?? "zh",
                voice: settings.pluginTTSVoice,
                audioFormat: "mp3",
                text: normalizeSpeechText(text),
                sampleRate: 24_000,
                bitrate: 128_000
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(data: data, response: response, prefix: "Soniox 语音合成失败")
        guard !data.isEmpty else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 23, userInfo: [NSLocalizedDescriptionKey: "Soniox 没有返回可播放音频"])
        }
        return AudioPlaybackPayload(
            data: data,
            fileExtension: audioFileExtension(from: response, fallbackData: data)
        )
    }

    private func configureSession() throws {
        // macOS 不需要 AVAudioSession 配置
    }

    private func resolvedAPIKey(_ value: String, fallback: String) -> String {
        let primary = normalizeAPIKey(value)
        if !primary.isEmpty {
            return primary
        }
        return normalizeAPIKey(fallback)
    }

    private func normalizedLanguageCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed != "auto" else { return nil }
        return trimmed
    }

    private func normalizeSpeechText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedAudioFileExtension(_ value: String?, data: Data) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if ["mp3", "wav", "m4a", "aac", "caf"].contains(trimmed) {
            return trimmed
        }
        if data.starts(with: [0x49, 0x44, 0x33]) || data.starts(with: [0xFF, 0xFB]) {
            return "mp3"
        }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return "wav"
        }
        return "mp3"
    }

    private func audioFileExtension(from response: URLResponse, fallbackData: Data) -> String {
        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("mpeg") || contentType.contains("mp3") {
            return "mp3"
        }
        if contentType.contains("wav") || contentType.contains("wave") {
            return "wav"
        }
        if contentType.contains("m4a") || contentType.contains("mp4") || contentType.contains("aac") {
            return "m4a"
        }
        return normalizedAudioFileExtension(nil, data: fallbackData)
    }

    private func makeCompatibleURL(base: String, path: String) throws -> URL {
        let normalizedBase = normalizeBaseURL(base)
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let urlString: String

        if normalizedBase.hasSuffix("/v1\(normalizedPath)") || normalizedBase.hasSuffix(normalizedPath) {
            urlString = normalizedBase
        } else if normalizedBase.hasSuffix("/v1") {
            urlString = normalizedBase + normalizedPath
        } else {
            urlString = normalizedBase + "/v1" + normalizedPath
        }

        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 30, userInfo: [NSLocalizedDescriptionKey: "无效的 API 地址"])
        }
        return url
    }

    private func makeDirectURL(base: String, path: String) throws -> URL {
        let normalizedBase = normalizeBaseURL(base)
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let urlString: String

        if normalizedBase.hasSuffix(normalizedPath) {
            urlString = normalizedBase
        } else {
            urlString = normalizedBase + normalizedPath
        }

        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 31, userInfo: [NSLocalizedDescriptionKey: "无效的 API 地址"])
        }
        return url
    }

    private func normalizeBaseURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "https://api.openai.com/v1" : trimmed
        let withScheme = candidate.contains("://") ? candidate : "https://\(candidate)"
        return withScheme.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a":
            return "audio/m4a"
        case "wav":
            return "audio/wav"
        case "mp3":
            return "audio/mpeg"
        default:
            return "application/octet-stream"
        }
    }

    private func makeMultipartBody(fileURL: URL, boundary: String, model: String, languageCode: String?) throws -> Data {
        var data = Data()

        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType(for: fileURL))\r\n\r\n".data(using: .utf8)!)
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n".data(using: .utf8)!)

        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        data.append("\(model)\r\n".data(using: .utf8)!)

        if let languageCode {
            data.append("--\(boundary)\r\n".data(using: .utf8)!)
            data.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
            data.append("\(languageCode)\r\n".data(using: .utf8)!)
        }

        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private func validateResponse(data: Data, response: URLResponse, prefix: String) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ChatBoxSpeechTranslationService", code: 40, userInfo: [NSLocalizedDescriptionKey: "\(prefix)：无效响应"])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "ChatBoxSpeechTranslationService",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message?.isEmpty == false ? "\(prefix)：\(message!)" : "\(prefix)：HTTP \(httpResponse.statusCode)"]
            )
        }
    }

    private func extractCompatibleProviderAudioData(data: Data, response: URLResponse) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            return data
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("application/json") {
            let json = try JSONSerialization.jsonObject(with: data)
            guard let object = json as? [String: Any] else { return data }

            let candidates: [String?] = [
                object["audio"] as? String,
                object["data"] as? String,
                object["audio_base64"] as? String,
                ((object["output"] as? [String: Any])?["audio"] as? [String: Any])?["data"] as? String
            ]

            for candidate in candidates {
                if let candidate, let decoded = Data(base64Encoded: candidate), !decoded.isEmpty {
                    return decoded
                }
            }
        }

        return data
    }

    private func uploadAudioFileToSoniox(fileURL: URL, baseURL: String, apiKey: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let requestURL = try makeCompatibleURL(base: baseURL, path: "/files")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeSonioxUploadBody(fileURL: fileURL, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(data: data, response: response, prefix: "Soniox 文件上传失败")
        return try JSONDecoder().decode(SonioxFileResponse.self, from: data).id
    }

    private func createSonioxTranscription(fileID: String, baseURL: String, apiKey: String, model: String, languageHints: [String]) async throws -> String {
        let requestURL = try makeCompatibleURL(base: baseURL, path: "/transcriptions")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            SonioxCreateTranscriptionRequest(
                model: model,
                fileID: fileID,
                languageHints: languageHints
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(data: data, response: response, prefix: "Soniox 创建转写任务失败")
        return try JSONDecoder().decode(SonioxTranscriptionResponse.self, from: data).id
    }

    private func waitForSonioxTranscription(id: String, baseURL: String, apiKey: String) async throws {
        let requestURL = try makeCompatibleURL(base: baseURL, path: "/transcriptions/\(id)")

        for _ in 0..<80 {
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            try validateResponse(data: data, response: response, prefix: "Soniox 查询转写状态失败")
            let decoded = try JSONDecoder().decode(SonioxTranscriptionResponse.self, from: data)

            switch decoded.status.lowercased() {
            case "completed":
                return
            case "queued", "processing", "running", "created":
                try await Task.sleep(nanoseconds: 500_000_000)
            default:
                throw NSError(domain: "ChatBoxSpeechTranslationService", code: 50, userInfo: [NSLocalizedDescriptionKey: "Soniox 转写失败：状态为 \(decoded.status)"])
            }
        }

        throw NSError(domain: "ChatBoxSpeechTranslationService", code: 51, userInfo: [NSLocalizedDescriptionKey: "Soniox 转写超时，请稍后重试"])
    }

    private func fetchSonioxTranscript(id: String, baseURL: String, apiKey: String) async throws -> SonioxTranscriptResponse {
        let requestURL = try makeCompatibleURL(base: baseURL, path: "/transcriptions/\(id)/transcript")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(data: data, response: response, prefix: "Soniox 获取转写文本失败")
        return try JSONDecoder().decode(SonioxTranscriptResponse.self, from: data)
    }

    private func deleteSonioxTranscription(id: String, baseURL: String, apiKey: String) async throws {
        let requestURL = try makeCompatibleURL(base: baseURL, path: "/transcriptions/\(id)")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func deleteSonioxFile(id: String, baseURL: String, apiKey: String) async throws {
        let requestURL = try makeCompatibleURL(base: baseURL, path: "/files/\(id)")
        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func makeSonioxUploadBody(fileURL: URL, boundary: String) throws -> Data {
        var data = Data()
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: \(mimeType(for: fileURL))\r\n\r\n".data(using: .utf8)!)
        data.append(try Data(contentsOf: fileURL))
        data.append("\r\n".data(using: .utf8)!)
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return data
    }

    private func sonioxTranscriptionModel(for model: String) -> String {
        switch model {
        case "stt-rt-v4", "stt-async-v4":
            return "stt-async-v4"
        default:
            return "stt-async-v4"
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            let continuation = playbackContinuation
            playbackContinuation = nil
            self.player = nil
            if let playbackURL {
                try? FileManager.default.removeItem(at: playbackURL)
            }
            playbackURL = nil
            if flag {
                continuation?.resume()
            } else {
                continuation?.resume(throwing: NSError(domain: "ChatBoxSpeechTranslationService", code: 60, userInfo: [NSLocalizedDescriptionKey: "音频播放失败"]))
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            let continuation = playbackContinuation
            playbackContinuation = nil
            self.player = nil
            if let playbackURL {
                try? FileManager.default.removeItem(at: playbackURL)
            }
            playbackURL = nil
            continuation?.resume(throwing: error ?? NSError(domain: "ChatBoxSpeechTranslationService", code: 61, userInfo: [NSLocalizedDescriptionKey: "音频解码失败"]))
        }
    }
}

private struct AudioPlaybackPayload {
    let data: Data
    let fileExtension: String
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private struct OpenAITTSPayload: Encodable {
    let model: String
    let voice: String
    let input: String
    let instructions: String?
    let responseFormat: String

    enum CodingKeys: String, CodingKey {
        case model
        case voice
        case input
        case instructions
        case responseFormat = "response_format"
    }
}

private struct SonioxTTSPayload: Encodable {
    let model: String
    let language: String
    let voice: String
    let audioFormat: String
    let text: String
    let sampleRate: Int
    let bitrate: Int

    enum CodingKeys: String, CodingKey {
        case model
        case language
        case voice
        case audioFormat = "audio_format"
        case text
        case sampleRate = "sample_rate"
        case bitrate
    }
}

private struct SonioxFileResponse: Decodable {
    let id: String
}

private struct SonioxCreateTranscriptionRequest: Encodable {
    let model: String
    let fileID: String
    let languageHints: [String]

    enum CodingKeys: String, CodingKey {
        case model
        case fileID = "file_id"
        case languageHints = "language_hints"
    }
}

private struct SonioxTranscriptionResponse: Decodable {
    let id: String
    let status: String
}

private struct SonioxTranscriptResponse: Decodable {
    let text: String
}

private struct ElevenLabsTTSPayload: Encodable {
    let text: String
    let modelID: String

    enum CodingKeys: String, CodingKey {
        case text
        case modelID = "model_id"
    }
}

private struct ElevenLabsSTTResponse: Decodable {
    let text: String
}

@MainActor
private final class AVSpeechSynthesisDelegateHandler: NSObject, AVSpeechSynthesizerDelegate {
    var synthesizer: AVSpeechSynthesizer?
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        complete(with: nil)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        complete(with: NSError(
            domain: "ChatBoxSpeechTranslationService",
            code: 29,
            userInfo: [NSLocalizedDescriptionKey: "系统语音朗读被中断"]
        ))
    }

    private func complete(with error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

func exportedConversationText(for session: ChatSession) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm"

    let header = [
        "标题：\(session.title)",
        "创建时间：\(formatter.string(from: Date(timeIntervalSince1970: session.createdAt / 1000)))",
        "更新时间：\(formatter.string(from: Date(timeIntervalSince1970: session.updatedAt / 1000)))",
        ""
    ]

    let body = session.messages
        .filter { $0.role != .system }
        .map { message -> String in
            let roleTitle: String
            switch message.role {
            case .user:
                roleTitle = "用户"
            case .assistant:
                roleTitle = "助手"
            case .system:
                roleTitle = "系统"
            }

            let timestamp = formatter.string(from: Date(timeIntervalSince1970: message.createdAt / 1000))
            let content = transcriptText(for: message)
            return "[\(roleTitle)] \(timestamp)\n\(content)\n"
        }

    return (header + body).joined(separator: "\n")
}

private func transcriptText(for message: ChatMessage) -> String {
    let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    if !content.isEmpty {
        return content
    }
    if let weatherCard = message.weatherCard {
        return weatherCardTranscript(weatherCard)
    }
    if let mapCard = message.mapCard {
        return mapCardTranscript(mapCard)
    }
    return ""
}

func structuredAssistantInstructionPrompt() -> String {
    """
    你支持结构化 UI 消息。

    当用户在询问某个城市、地区或地点的天气、温度、未来几天预报、今日天气、降雨、体感、穿衣建议等天气信息时，优先返回天气卡片 JSON，而不是普通正文。

    当用户出现下面任一类意图时，必须返回地图卡片 JSON，而不是自然语言正文：
    - 明确说想去、要去、准备去、打算去某个地方
    - 询问去哪、去哪里、哪里值得去、某地值不值得去
    - 询问某个地点、地标、市场、餐厅、商场、景点，并且语义上是在表达到访、游玩、出行、探店、旅行意图

    满足上述条件时：
    - 只返回一个 JSON 对象
    - 不要输出 Markdown
    - 不要输出解释文字
    - 不要把 JSON 放进代码块
    - 除了地图字段，还必须提供可直接展示在地图卡片内/详情页的详细介绍正文

    地图卡片 JSON 格式：
    {
      "type": "map_card",
      "title": "地点名称",
      "subtitle": "地点副标题，可选",
      "lat": 0,
      "lng": 0,
      "rating": 0,
      "opening_hours": "营业时间，可选",
      "address": "地址，可选",
      "website": "网站，可选",
      "phone": "电话，可选",
      "text": "关于这个地点的详细介绍，必填。请优先包含：历史、文化体验、周边环境、游览建议。可使用小标题和列表。",
      "history": ["历史要点1", "历史要点2"],
      "culture": ["文化体验1", "文化体验2"],
      "surroundings": ["周边环境1", "周边环境2"],
      "tips": ["游览建议1", "游览建议2"]
    }

    也可以使用：
    {
      "message_type": "map_card",
      "place": {
        "name": "地点名称",
        "lat": 0,
        "lng": 0
      }
    }

    如果返回 map_card：
    - `text` 必须非空
    - `text` 应该介绍这个地点为什么值得去，不要只重复标题和评分
    - `text` 默认应覆盖：历史、文化体验、周边环境、游览建议
    - 如果能结构化输出，优先额外提供 `history`、`culture`、`surroundings`、`tips`
    - 不要提及地图服务实现细节，不要输出 Yandex API、API Key、provider、地图 SDK 等技术内容
    - 如果用户表达的是“想去某地/要去某地”，无论内容长短，都必须返回 `map_card`

    天气卡片 JSON 格式：
    {
      "type": "weather_card",
      "location": "阿拉木图，哈萨克斯坦",
      "condition": "云量增加",
      "current_temp_c": 18,
      "text": "对当前天气和未来趋势的简要总结，必填。",
      "source": "weather.com，可选",
      "daily_forecast": [
        { "day": "周四", "icon": "partly_cloudy", "high_c": 27, "low_c": 14 },
        { "day": "周五", "icon": "rain", "high_c": 19, "low_c": 8 }
      ],
      "hourly_forecast": [
        { "time": "10上午", "temp_c": 23 },
        { "time": "1下午", "temp_c": 26 }
      ]
    }

    如果返回 weather_card：
    - `text` 必须非空
    - `daily_forecast` 建议提供 5 到 7 条
    - `hourly_forecast` 建议提供 6 到 8 条
    - `icon` 使用简洁英文枚举，例如：sunny、partly_cloudy、cloudy、rain、storm、snow、wind、fog
    - 温度统一使用摄氏度字段
    - 不要输出 Markdown，不要输出解释文字，不要把 JSON 放进代码块

    如果不适合展示地图卡片，就正常返回自然语言文本。
    """
}

func parseStructuredWeatherMessage(from rawContent: String) -> StructuredWeatherCardEnvelope? {
    let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let jsonText = extractJSONObjectCandidate(from: trimmed),
          let data = jsonText.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    let type = stringValue(root["message_type"]) ?? stringValue(root["type"]) ?? ""
    guard type.lowercased() == ChatMessageType.weatherCard.rawValue else {
        return nil
    }

    guard let location = firstNonEmptyString([stringValue(root["location"]), stringValue(root["title"])]),
          let currentTempC = doubleValue(root["current_temp_c"]) ?? doubleValue(root["currentTempC"]) ?? doubleValue(root["temp_c"])
    else {
        return nil
    }

    let condition = firstNonEmptyString([stringValue(root["condition"]), stringValue(root["summary"])]) ?? "天气更新"

    let dailyForecasts = parseDailyForecasts(root["daily_forecast"] as? [[String: Any]] ?? root["dailyForecast"] as? [[String: Any]] ?? [])
    let hourlyPoints = parseHourlyForecasts(root["hourly_forecast"] as? [[String: Any]] ?? root["hourlyForecast"] as? [[String: Any]] ?? [])

    let weatherCard = WeatherCardPayload(
        location: location,
        condition: condition,
        currentTempC: currentTempC,
        dailyForecasts: dailyForecasts,
        hourlyPoints: hourlyPoints,
        source: firstNonEmptyString([stringValue(root["source"]), stringValue(root["provider"])])
    )

    let displayText = buildWeatherCardDisplayText(root: root)
    return StructuredWeatherCardEnvelope(weatherCard: weatherCard, displayText: displayText)
}

func parseStructuredWeatherPreview(from rawContent: String) -> WeatherCardPayload? {
    let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.contains("\"weather_card\"") || trimmed.contains("weather_card") else { return nil }

    guard let location = firstNonEmptyString([partialStringValue(in: trimmed, key: "location"), partialStringValue(in: trimmed, key: "title")]),
          let currentTempC = partialDoubleValue(in: trimmed, key: "current_temp_c") ?? partialDoubleValue(in: trimmed, key: "temp_c")
    else {
        return nil
    }

    return WeatherCardPayload(
        location: location,
        condition: partialStringValue(in: trimmed, key: "condition") ?? "天气更新",
        currentTempC: currentTempC,
        dailyForecasts: [],
        hourlyPoints: [],
        source: partialStringValue(in: trimmed, key: "source")
    )
}

func looksLikeStructuredWeatherCardOutput(_ rawContent: String) -> Bool {
    let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard trimmed.first == "{" || trimmed.first == "[" else { return false }

    let markers = [
        "\"weather_card\"",
        "\"current_temp_c\"",
        "\"daily_forecast\"",
        "\"hourly_forecast\"",
        "\"condition\"",
        "\"location\""
    ]

    return markers.contains { trimmed.contains($0) }
}

func parseStructuredAssistantMessage(from rawContent: String) -> StructuredMapCardEnvelope? {
    let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let jsonText = extractJSONObjectCandidate(from: trimmed),
          let data = jsonText.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }

    let type = stringValue(root["message_type"]) ?? stringValue(root["type"]) ?? ""
    guard type.lowercased() == ChatMessageType.mapCard.rawValue else {
        return nil
    }

    let place = root["place"] as? [String: Any]
    let title = firstNonEmptyString([
        stringValue(root["title"]),
        stringValue(place?["name"]),
        stringValue(place?["title"])
    ])
    guard let latitude = doubleValue(root["lat"]) ?? doubleValue(place?["lat"]),
          let longitude = doubleValue(root["lng"]) ?? doubleValue(place?["lng"]),
          let title else {
        return nil
    }

    let mapCard = MapCardPayload(
        title: title,
        subtitle: firstNonEmptyString([
            stringValue(root["subtitle"]),
            stringValue(place?["subtitle"]),
            stringValue(place?["category"])
        ]),
        latitude: latitude,
        longitude: longitude,
        rating: doubleValue(root["rating"]) ?? doubleValue(place?["rating"]),
        openingHours: firstNonEmptyString([
            stringValue(root["opening_hours"]),
            stringValue(root["openingHour"]),
            stringValue(root["openingHours"]),
            stringValue(place?["opening_hours"])
        ]),
        address: firstNonEmptyString([
            stringValue(root["address"]),
            stringValue(place?["address"])
        ]),
        website: firstNonEmptyString([
            stringValue(root["website"]),
            stringValue(place?["website"])
        ]),
        phone: firstNonEmptyString([
            stringValue(root["phone"]),
            stringValue(place?["phone"])
        ])
    )

    let displayText = buildMapCardDisplayText(root: root, place: place)

    return StructuredMapCardEnvelope(mapCard: mapCard, displayText: displayText)
}

func parseStructuredAssistantPreview(from rawContent: String) -> MapCardPayload? {
    let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    guard trimmed.contains("\"map_card\"") || trimmed.contains("map_card") else { return nil }

    let title = firstNonEmptyString([
        partialStringValue(in: trimmed, key: "title"),
        partialStringValue(in: trimmed, key: "name")
    ])
    guard let latitude = partialDoubleValue(in: trimmed, key: "lat"),
          let longitude = partialDoubleValue(in: trimmed, key: "lng"),
          let title else {
        return nil
    }

    return MapCardPayload(
        title: title,
        subtitle: firstNonEmptyString([
            partialStringValue(in: trimmed, key: "subtitle"),
            partialStringValue(in: trimmed, key: "category")
        ]),
        latitude: latitude,
        longitude: longitude,
        rating: partialDoubleValue(in: trimmed, key: "rating"),
        openingHours: firstNonEmptyString([
            partialStringValue(in: trimmed, key: "opening_hours"),
            partialStringValue(in: trimmed, key: "openingHour"),
            partialStringValue(in: trimmed, key: "openingHours")
        ]),
        address: partialStringValue(in: trimmed, key: "address"),
        website: partialStringValue(in: trimmed, key: "website"),
        phone: partialStringValue(in: trimmed, key: "phone")
    )
}

func looksLikeStructuredMapCardOutput(_ rawContent: String) -> Bool {
    let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    guard trimmed.first == "{" || trimmed.first == "[" else { return false }

    let markers = [
        "\"map_card\"",
        "\"message_type\"",
        "\"type\"",
        "\"place\"",
        "\"lat\"",
        "\"lng\"",
        "\"title\""
    ]

    return markers.contains { trimmed.contains($0) }
}

private func buildMapCardDisplayText(root: [String: Any], place: [String: Any]?) -> String {
    let primaryText = firstNonEmptyString([
        stringValue(root["text"]),
        stringValue(root["content"]),
        stringValue(root["details"]),
        stringValue(root["about"]),
        stringValue(root["description"]),
        stringValue(place?["text"]),
        stringValue(place?["description"])
    ])

    let sectionsText = markdownTextFromSections(root["sections"] as? [[String: Any]])
    let historyText = markdownBulletList(
        title: "历史",
        values: stringArray(root["history"]) ?? stringArray(place?["history"])
    )
    let cultureText = markdownBulletList(
        title: "文化体验",
        values: stringArray(root["culture"]) ?? stringArray(root["cultural_experience"]) ?? stringArray(place?["culture"])
    )
    let surroundingsText = markdownBulletList(
        title: "周边环境",
        values: stringArray(root["surroundings"]) ?? stringArray(root["nearby_environment"]) ?? stringArray(place?["surroundings"])
    )
    let nearbyText = markdownBulletList(
        title: "附近地标",
        values: stringArray(root["nearby"]) ?? stringArray(place?["nearby"])
    )
    let highlightsText = markdownBulletList(
        title: "主要特色",
        values: stringArray(root["highlights"]) ?? stringArray(place?["highlights"])
    )
    let tipsText = markdownBulletList(
        title: "游览建议",
        values: stringArray(root["tips"]) ?? stringArray(place?["tips"])
    )

    return [
        primaryText,
        sectionsText,
        historyText,
        cultureText,
        surroundingsText,
        nearbyText,
        highlightsText,
        tipsText
    ]
    .compactMap { value in
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    .joined(separator: "\n\n")
}

private func buildWeatherCardDisplayText(root: [String: Any]) -> String {
    [
        stringValue(root["text"]),
        stringValue(root["summary"]),
        stringValue(root["details"]),
        stringValue(root["description"])
    ]
    .compactMap { value in
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    .joined(separator: "\n\n")
}

private func parseDailyForecasts(_ rows: [[String: Any]]) -> [WeatherDailyForecastPayload] {
    rows.compactMap { row in
        guard let day = firstNonEmptyString([stringValue(row["day"]), stringValue(row["label"])]),
              let high = doubleValue(row["high_c"]) ?? doubleValue(row["highC"]),
              let low = doubleValue(row["low_c"]) ?? doubleValue(row["lowC"])
        else {
            return nil
        }

        return WeatherDailyForecastPayload(
            day: day,
            iconName: firstNonEmptyString([stringValue(row["icon"]), stringValue(row["icon_name"])]) ?? "cloudy",
            highC: high,
            lowC: low
        )
    }
}

private func parseHourlyForecasts(_ rows: [[String: Any]]) -> [WeatherHourlyPointPayload] {
    rows.compactMap { row in
        guard let time = firstNonEmptyString([stringValue(row["time"]), stringValue(row["label"])]),
              let temp = doubleValue(row["temp_c"]) ?? doubleValue(row["tempC"])
        else {
            return nil
        }

        return WeatherHourlyPointPayload(time: time, tempC: temp)
    }
}

private func extractJSONObjectCandidate(from text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.hasPrefix("```") {
        let lines = trimmed.components(separatedBy: .newlines)
        if lines.count >= 3 {
            let body = lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if body.hasPrefix("{"), body.hasSuffix("}") {
                return body
            }
        }
    }

    if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
        return trimmed
    }

    if let embedded = extractBalancedJSONObject(from: trimmed) {
        return embedded
    }

    return nil
}

private func extractBalancedJSONObject(from text: String) -> String? {
    let characters = Array(text)
    var startIndex: Int?
    var depth = 0
    var isInsideString = false
    var isEscaping = false

    for index in characters.indices {
        let character = characters[index]

        if isEscaping {
            isEscaping = false
            continue
        }

        if character == "\\" && isInsideString {
            isEscaping = true
            continue
        }

        if character == "\"" {
            isInsideString.toggle()
            continue
        }

        if isInsideString {
            continue
        }

        if character == "{" {
            if depth == 0 {
                startIndex = index
            }
            depth += 1
        } else if character == "}" {
            guard depth > 0 else { continue }
            depth -= 1
            if depth == 0, let startIndex {
                let candidate = String(characters[startIndex...index]).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.contains("\"type\"") || candidate.contains("\"message_type\"") {
                    return candidate
                }
            }
        }
    }

    return nil
}

private func stringValue(_ value: Any?) -> String? {
    if let string = value as? String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    return nil
}

private func doubleValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let string = value as? String {
        return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return nil
}

private func firstNonEmptyString(_ values: [String?]) -> String? {
    values.first { value in
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } ?? nil
}

private func stringArray(_ value: Any?) -> [String]? {
    guard let values = value as? [Any] else { return nil }
    let output = values.compactMap { item -> String? in
        if let string = item as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
    return output.isEmpty ? nil : output
}

private func markdownTextFromSections(_ sections: [[String: Any]]?) -> String? {
    guard let sections, !sections.isEmpty else { return nil }
    let blocks = sections.compactMap { section -> String? in
        let title = stringValue(section["title"])
        let content = firstNonEmptyString([
            stringValue(section["content"]),
            stringValue(section["text"]),
            stringValue(section["description"])
        ])
        guard title != nil || content != nil else { return nil }
        return [title.map { "## \($0)" }, content]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
    return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n")
}

private func markdownBulletList(title: String, values: [String]?) -> String? {
    guard let values, !values.isEmpty else { return nil }
    return "## \(title)\n" + values.map { "- \($0)" }.joined(separator: "\n")
}

private func partialStringValue(in text: String, key: String) -> String? {
    let pattern = #""\#(key)"\s*:\s*"((?:\\.|[^"\\])*)""#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let valueRange = Range(match.range(at: 1), in: text) else {
        return nil
    }
    let value = String(text[valueRange])
        .replacingOccurrences(of: #"\""#, with: "\"", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
}

private func partialDoubleValue(in text: String, key: String) -> Double? {
    let pattern = #""\#(key)"\s*:\s*(-?\d+(?:\.\d+)?)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let match = regex.firstMatch(in: text, range: range),
          let valueRange = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return Double(String(text[valueRange]))
}

func yandexStaticMapURL(
    latitude: Double,
    longitude: Double,
    apiKey: String,
    width: Int = 640,
    height: Int = 320,
    isDark: Bool = false
) -> URL? {
    let normalizedKey = normalizeAPIKey(apiKey)
    guard !normalizedKey.isEmpty else { return nil }

    var components = URLComponents(string: "https://static-maps.yandex.ru/v1")
    var items: [URLQueryItem] = [
        .init(name: "lang", value: "en_US"),
        .init(name: "ll", value: "\(longitude),\(latitude)"),
        .init(name: "z", value: "16"),
        .init(name: "size", value: "\(min(width, 650)),\(min(height, 450))"),
        .init(name: "scale", value: "2"),
        .init(name: "pt", value: "\(longitude),\(latitude),pm2rdm"),
        .init(name: "apikey", value: normalizedKey)
    ]

    if isDark {
        items.append(.init(name: "theme", value: "dark"))
    }

    components?.queryItems = items
    return components?.url
}
