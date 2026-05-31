import AVFoundation
import Foundation

struct ProviderMeta: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let icon: String
    let defaultBaseURL: String
    let defaultModelsCSV: String
    let defaultFavoritesCSV: String
}

let providerList: [ProviderMeta] = [
    .init(id: "custom", title: "自定义", icon: "✎", defaultBaseURL: "", defaultModelsCSV: "custom-model", defaultFavoritesCSV: "custom-model"),
    .init(id: "deepseek", title: "DeepSeek", icon: "◆", defaultBaseURL: "https://api.deepseek.com/v1", defaultModelsCSV: "deepseek-chat,deepseek-reasoner", defaultFavoritesCSV: "deepseek-chat"),
    .init(id: "openai", title: "OpenAI", icon: "◉", defaultBaseURL: "https://api.openai.com/v1", defaultModelsCSV: "gpt-4o-mini,gpt-4.1-mini", defaultFavoritesCSV: "gpt-4o-mini"),
    .init(id: "openrouter", title: "OpenRouter", icon: "⬡", defaultBaseURL: "https://openrouter.ai/api/v1", defaultModelsCSV: "openai/gpt-4o-mini,deepseek/deepseek-chat-v3-0324,anthropic/claude-3.5-sonnet", defaultFavoritesCSV: "openai/gpt-4o-mini"),
    .init(id: "qwen", title: "Qwen", icon: "◌", defaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModelsCSV: "qwen-plus,qwen-max", defaultFavoritesCSV: "qwen-plus"),
    .init(id: "glm", title: "GLM", icon: "◎", defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4", defaultModelsCSV: "glm-4-plus,glm-4-flash", defaultFavoritesCSV: "glm-4-flash"),
    .init(id: "kimi", title: "Kimi", icon: "◐", defaultBaseURL: "https://api.moonshot.cn/v1", defaultModelsCSV: "moonshot-v1-8k,moonshot-v1-32k", defaultFavoritesCSV: "moonshot-v1-8k"),
    .init(id: "siliconflow", title: "硅基流动", icon: "◈", defaultBaseURL: "https://api.siliconflow.cn/v1", defaultModelsCSV: "Qwen/Qwen2.5-7B-Instruct,deepseek-ai/DeepSeek-V3", defaultFavoritesCSV: "Qwen/Qwen2.5-7B-Instruct"),
    .init(id: "minimax", title: "MiniMax", icon: "◍", defaultBaseURL: "https://api.minimax.chat/v1", defaultModelsCSV: "MiniMax-Text-01,abab6.5s-chat", defaultFavoritesCSV: "MiniMax-Text-01"),
    .init(id: "gemini", title: "Gemini", icon: "✦", defaultBaseURL: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModelsCSV: "gemini-2.0-flash,gemini-1.5-pro", defaultFavoritesCSV: "gemini-2.0-flash"),
    .init(id: "grok", title: "Grok", icon: "✧", defaultBaseURL: "https://api.x.ai/v1", defaultModelsCSV: "grok-2-1212,grok-2-vision-1212", defaultFavoritesCSV: "grok-2-1212"),
    .init(id: "claude", title: "Claude", icon: "◒", defaultBaseURL: "https://api.anthropic.com/v1", defaultModelsCSV: "claude-3-5-sonnet-20241022,claude-3-5-haiku-20241022", defaultFavoritesCSV: "claude-3-5-sonnet-20241022")
]

func providerMeta(for provider: String) -> ProviderMeta {
    providerList.first(where: { $0.id == provider }) ?? providerList[0]
}

func providerTitle(for provider: String) -> String {
    providerMeta(for: provider).title
}

func normalizeProviderID(_ provider: String) -> String {
    providerList.contains(where: { $0.id == provider }) ? provider : "deepseek"
}

func defaultBaseURL(for provider: String) -> String {
    providerMeta(for: provider).defaultBaseURL
}

func defaultModelsCSV(for provider: String) -> String {
    providerMeta(for: provider).defaultModelsCSV
}

func providerMap(from json: String) -> [String: String] {
    guard let data = json.data(using: .utf8),
          let value = try? JSONDecoder().decode([String: String].self, from: data) else {
        return [:]
    }
    return value
}

func jsonString(from map: [String: String]) -> String {
    guard let data = try? JSONEncoder().encode(map),
          let text = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return text
}

enum SpeechServiceProvider: String, Codable, CaseIterable, Identifiable {
    case soniox
    case openai
    case elevenlabs
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .soniox: return "Soniox"
        case .openai: return "OpenAI"
        case .elevenlabs: return "ElevenLabs"
        case .system: return "系统"
        }
    }

    var requiresAPIKey: Bool {
        self != .system
    }

    var defaultSTTBaseURL: String {
        switch self {
        case .soniox: return "https://api.soniox.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .elevenlabs: return "https://api.elevenlabs.io/v1"
        case .system: return ""
        }
    }

    var defaultTTSBaseURL: String {
        switch self {
        case .soniox: return "https://tts-rt.soniox.com/tts"
        case .openai: return "https://api.openai.com/v1"
        case .elevenlabs: return "https://api.elevenlabs.io/v1"
        case .system: return ""
        }
    }
}

struct SpeechVoiceOption: Identifiable, Hashable {
    let id: String
    let title: String
}

func normalizeSpeechProviderID(_ provider: String) -> String {
    let normalized = provider.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let match = SpeechServiceProvider(rawValue: normalized) {
        return match.rawValue
    }
    if normalized.contains("eleven") {
        return SpeechServiceProvider.elevenlabs.rawValue
    }
    if normalized == "macos" || normalized == "apple" || normalized == "本地" {
        return SpeechServiceProvider.system.rawValue
    }
    return SpeechServiceProvider.soniox.rawValue
}

func speechProviderRequiresAPIKey(_ provider: String) -> Bool {
    SpeechServiceProvider(rawValue: normalizeSpeechProviderID(provider))?.requiresAPIKey ?? true
}

func defaultSpeechTTSModel(for provider: String) -> String {
    speechTTSPModels(for: provider).first ?? "tts-rt-v1"
}

func defaultSpeechTTSVoice(for provider: String) -> String {
    speechTTSVoiceOptions(for: provider).first?.id ?? "Maya"
}

func defaultSpeechSTTModel(for provider: String) -> String {
    speechSTTModels(for: provider).first ?? "stt-async-v4"
}

func speechTTSPModels(for provider: String) -> [String] {
    switch normalizeSpeechProviderID(provider) {
    case SpeechServiceProvider.openai.rawValue:
        return ["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]
    case SpeechServiceProvider.elevenlabs.rawValue:
        return ["eleven_multilingual_v2", "eleven_turbo_v2_5", "eleven_flash_v2_5"]
    case SpeechServiceProvider.system.rawValue:
        return ["default"]
    default:
        return ["tts-rt-v1"]
    }
}

func speechTTSVoiceOptions(for provider: String) -> [SpeechVoiceOption] {
    switch normalizeSpeechProviderID(provider) {
    case SpeechServiceProvider.openai.rawValue:
        return ["alloy", "echo", "fable", "onyx", "nova", "shimmer"].map { SpeechVoiceOption(id: $0, title: $0.capitalized) }
    case SpeechServiceProvider.elevenlabs.rawValue:
        return [
            SpeechVoiceOption(id: "21m00Tcm4TlvDq8ikWAM", title: "Rachel"),
            SpeechVoiceOption(id: "pNInz6obpgDQGcFmaJgB", title: "Adam"),
            SpeechVoiceOption(id: "EXAVITQu4vr4xnSDxMaL", title: "Bella"),
            SpeechVoiceOption(id: "ErXwobaYiN019PkySvjV", title: "Antoni"),
            SpeechVoiceOption(id: "MF3mGyEYCl7XYWbV9V6O", title: "Elli"),
            SpeechVoiceOption(id: "TxGEqnHWrfWFTfGW9XjX", title: "Josh")
        ]
    case SpeechServiceProvider.system.rawValue:
        return systemSpeechVoices()
    default:
        return ["Maya", "Jace", "Leon"].map { SpeechVoiceOption(id: $0, title: $0) }
    }
}

func speechSTTModels(for provider: String) -> [String] {
    switch normalizeSpeechProviderID(provider) {
    case SpeechServiceProvider.openai.rawValue:
        return ["gpt-4o-mini-transcribe", "whisper-1"]
    case SpeechServiceProvider.elevenlabs.rawValue:
        return ["scribe_v1", "scribe_v1_experimental"]
    case SpeechServiceProvider.system.rawValue:
        return ["zh-CN", "en-US", "ja-JP", "ko-KR", "yue-CN"]
    default:
        return ["stt-async-v4", "stt-rt-v4"]
    }
}

func systemSpeechLocaleTitle(_ identifier: String) -> String {
    switch identifier {
    case "zh-CN": return "简体中文"
    case "en-US": return "英语（美国）"
    case "ja-JP": return "日语"
    case "ko-KR": return "韩语"
    case "yue-CN": return "粤语"
    default: return identifier
    }
}

func systemSpeechVoices() -> [SpeechVoiceOption] {
    AVSpeechSynthesisVoice.speechVoices().map { voice in
        let title = voice.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return SpeechVoiceOption(
            id: voice.identifier,
            title: title.isEmpty ? voice.identifier : title
        )
    }
    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
}

func speechProviderTitle(for provider: String) -> String {
    SpeechServiceProvider(rawValue: normalizeSpeechProviderID(provider))?.title ?? SpeechServiceProvider.soniox.title
}

func defaultSpeechSTTBaseURL(for provider: String) -> String {
    SpeechServiceProvider(rawValue: normalizeSpeechProviderID(provider))?.defaultSTTBaseURL ?? SpeechServiceProvider.soniox.defaultSTTBaseURL
}

func defaultSpeechTTSBaseURL(for provider: String) -> String {
    SpeechServiceProvider(rawValue: normalizeSpeechProviderID(provider))?.defaultTTSBaseURL ?? SpeechServiceProvider.soniox.defaultTTSBaseURL
}
