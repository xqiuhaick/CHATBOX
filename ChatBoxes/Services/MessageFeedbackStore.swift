import Foundation

enum MessageFeedbackValue: String, Codable {
    case up
    case down
}

@MainActor
@Observable
final class MessageFeedbackStore {
    static let shared = MessageFeedbackStore()

    private let key = "chatbox.messageFeedback"
    private var cache: [String: MessageFeedbackValue] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let map = try? JSONDecoder().decode([String: MessageFeedbackValue].self, from: data) {
            cache = map
        }
    }

    func feedback(for messageID: String) -> MessageFeedbackValue? {
        cache[messageID]
    }

    func setFeedback(_ value: MessageFeedbackValue?, for messageID: String) {
        if let value {
            cache[messageID] = value
        } else {
            cache.removeValue(forKey: messageID)
        }
        persist()
    }

    func toggle(_ value: MessageFeedbackValue, for messageID: String) {
        if cache[messageID] == value {
            setFeedback(nil, for: messageID)
        } else {
            setFeedback(value, for: messageID)
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
