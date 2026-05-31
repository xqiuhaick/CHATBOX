import Foundation
import SwiftUI

enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

enum ChatMessageType: String, Codable {
    case text
    case mapCard = "map_card"
    case weatherCard = "weather_card"
    case imageCard = "image_card"
}

struct MapCardPayload: Codable, Equatable {
    var title: String
    var subtitle: String?
    var latitude: Double
    var longitude: Double
    var rating: Double?
    var openingHours: String?
    var address: String?
    var website: String?
    var phone: String?

    var coordinateText: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }
}

struct WeatherDailyForecastPayload: Codable, Equatable, Identifiable {
    var id: String { day + iconName + String(highC) + String(lowC) }
    var day: String
    var iconName: String
    var highC: Double
    var lowC: Double
}

struct WeatherHourlyPointPayload: Codable, Equatable, Identifiable {
    var id: String { time + String(tempC) }
    var time: String
    var tempC: Double
}

struct WeatherCardPayload: Codable, Equatable {
    var location: String
    var condition: String
    var currentTempC: Double
    var dailyForecasts: [WeatherDailyForecastPayload]
    var hourlyPoints: [WeatherHourlyPointPayload]
    var source: String?

    var currentTempF: Double {
        currentTempC * 9 / 5 + 32
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: String
    var role: MessageRole
    var content: String
    var messageType: ChatMessageType?
    var mapCard: MapCardPayload?
    var weatherCard: WeatherCardPayload?
    var fileName: String?
    var fileExt: String?
    var fileText: String?
    var reasoningContent: String?
    var reasoningDurationSec: Int?
    var expectReasoning: Bool?
    var searchQuery: String?
    var searchDate: String?
    var searchSummary: String?
    var searchInProgress: Bool?
    var searchResultCount: Int?
    var searchResults: [WebSearchResultItem]?
    /// 发送时输入栏「搜索」按钮是否开启（仅该条消息是否联网搜索）
    var webSearchRequested: Bool?
    let createdAt: TimeInterval
    var imageDataURL: String?
    var generating: Bool?
    var error: Bool?
}

struct WebSearchResultItem: Identifiable, Codable, Equatable {
    var title: String
    var snippet: String
    var url: String

    var id: String { url }
}

struct ChatSession: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    let createdAt: TimeInterval
    var updatedAt: TimeInterval
    var messages: [ChatMessage]
}

enum AppCopy {
    static let appName = "ChatBoxes"
    static let defaultComposerPlaceholder = "询问任何问题"

    static func composerPlaceholder(from settings: AppSettings) -> String {
        let custom = settings.customComposerPlaceholder.trimmingCharacters(in: .whitespacesAndNewlines)
        return custom.isEmpty ? defaultComposerPlaceholder : custom
    }
}

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum AppGlassIntensity: String, Codable, CaseIterable, Identifiable {
    case subtle
    case standard
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: return "透明"
        case .standard: return "标准"
        case .strong: return "强调"
        }
    }

    func liquidGlass(interactive: Bool = false) -> Glass {
        let glass: Glass = switch self {
        case .subtle: .clear
        case .standard: .regular
        case .strong: .regular.tint(Color.primary.opacity(0.12))
        }
        return interactive ? glass.interactive() : glass
    }
}

enum WebSearchEngineOption: String, Codable, CaseIterable, Identifiable {
    case bing
    case google
    case baidu
    case duckduckgo
    case tavily

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bing: return "Bing"
        case .google: return "Google"
        case .baidu: return "百度"
        case .duckduckgo: return "DuckDuckGo"
        case .tavily: return "Tavily API"
        }
    }
}

enum ConversationTitleUpdateMode: String, Codable, CaseIterable, Identifiable {
    case firstMessage = "首次发送消息后"
    case everyMessage = "每次发送消息后"
    case manualOnly = "仅手动更新"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum MapProviderOption: String, Codable, CaseIterable, Identifiable {
    case yandex

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yandex: return "Yandex"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var provider: String = "deepseek"
    var apiKey: String = ""
    var baseURL: String = "https://api.deepseek.com/v1"
    var openAIAPIKey: String = ""
    var openAIBaseURL: String = "https://api.openai.com/v1"
    var openAIModelsCSV: String = "gpt-4o-mini,gpt-4.1-mini"
    var openAIFavoritesCSV: String = ""
    var deepSeekAPIKey: String = ""
    var deepSeekBaseURL: String = "https://api.deepseek.com/v1"
    var deepSeekModelsCSV: String = "deepseek-chat,deepseek-reasoner"
    var deepSeekFavoritesCSV: String = ""
    var providerAPIKeysJSON: String = ""
    var providerBaseURLsJSON: String = ""
    var providerModelsJSON: String = ""
    var providerFavoritesJSON: String = ""
    var webSearchEnabled: Bool = false
    var webSearchEngine: String = WebSearchEngineOption.tavily.rawValue
    var webSearchShowBrowser: Bool = false
    var webSearchLang: String = "zh-CN"
    var webSearchExcludeSites: String = ""
    var webSearchResultLimit: Int = 5
    var tavilyAPIKey: String = ""
    var hapticsEnabled: Bool = true
    var appearanceMode: AppAppearanceMode = .system
    var glassIntensity: AppGlassIntensity = .standard
    var model: String = "deepseek-chat"
    var pluginTitleProvider: String = "deepseek"
    var pluginTitleModel: String = "deepseek-chat"
    var pluginTitleUpdateMode: ConversationTitleUpdateMode = .firstMessage
    var pluginTTSProvider: String = SpeechServiceProvider.soniox.rawValue
    var pluginTTSAPIKey: String = ""
    var pluginTTSBaseURL: String = "https://tts-rt.soniox.com/tts"
    var pluginTTSModel: String = "tts-rt-v1"
    var pluginTTSVoice: String = "Maya"
    var pluginTTSPrompt: String = ""
    var pluginSTTAddRecordingAsFile: Bool = false
    var pluginSTTProvider: String = SpeechServiceProvider.soniox.rawValue
    var pluginSTTAPIKey: String = ""
    var pluginSTTBaseURL: String = "https://api.soniox.com/v1"
    var pluginSTTModel: String = "stt-async-v4"
    var translationSourceLanguageCode: String = "auto"
    var translationTargetLanguageCode: String = "en"
    var pluginVisionProvider: String = "openai"
    var pluginVisionModel: String = "gpt-4.1-mini"
    var pluginMapProvider: String = MapProviderOption.yandex.rawValue
    var pluginMapAPIKey: String = ""
    var customComposerPlaceholder: String = ""
    var showMessageTimestamps: Bool = false
    var sendWithCommandReturn: Bool = false
    var defaultWebSearchEnabled: Bool = false
    var activeGPTPresetID: String = ""
    var activeGPTInstructions: String = ""
}

struct TranslationLanguageOption: Identifiable, Hashable {
    let code: String
    let title: String
    let promptName: String
    let localeIdentifier: String

    var id: String { code }
}

let translationLanguageOptions: [TranslationLanguageOption] = [
    .init(code: "auto", title: "自动检测", promptName: "Auto Detect", localeIdentifier: "und"),
    .init(code: "zh", title: "中文", promptName: "Chinese", localeIdentifier: "zh-CN"),
    .init(code: "en", title: "英语", promptName: "English", localeIdentifier: "en-US"),
    .init(code: "ja", title: "日语", promptName: "Japanese", localeIdentifier: "ja-JP"),
    .init(code: "ko", title: "韩语", promptName: "Korean", localeIdentifier: "ko-KR"),
    .init(code: "fr", title: "法语", promptName: "French", localeIdentifier: "fr-FR"),
    .init(code: "de", title: "德语", promptName: "German", localeIdentifier: "de-DE"),
    .init(code: "es", title: "西班牙语", promptName: "Spanish", localeIdentifier: "es-ES"),
    .init(code: "ru", title: "俄语", promptName: "Russian", localeIdentifier: "ru-RU"),
    .init(code: "ar", title: "阿拉伯语", promptName: "Arabic", localeIdentifier: "ar-SA"),
    .init(code: "pt", title: "葡萄牙语", promptName: "Portuguese", localeIdentifier: "pt-PT"),
    .init(code: "it", title: "意大利语", promptName: "Italian", localeIdentifier: "it-IT")
]

struct ChatCompletionMessage: Codable {
    var role: String
    var content: ContentValue

    enum ContentValue: Codable {
        case text(String)
        case parts([ChatContentPart])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) {
                self = .text(text)
                return
            }
            self = .parts(try container.decode([ChatContentPart].self))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .parts(let parts):
                try container.encode(parts)
            }
        }
    }
}

struct ChatContentPart: Codable {
    var type: String
    var text: String?
    var imageURL: ChatImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

struct ChatImageURL: Codable {
    var url: String
}
