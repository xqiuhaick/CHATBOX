import Foundation

final class StorageService {
    static let shared = StorageService()

    private let sessionsKey = "chatbox.sessions"
    private let settingsKey = "chatbox.settings"
    private let defaults = UserDefaults.standard

    func getSessions() -> [ChatSession] {
        guard let data = defaults.data(forKey: sessionsKey),
              let sessions = try? JSONDecoder().decode([ChatSession].self, from: data) else {
            return []
        }
        return sessions
    }

    func saveSessions(_ sessions: [ChatSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: sessionsKey)
    }

    func getSettings() -> AppSettings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    private let libraryKey = "chatbox.library"
    private let projectsKey = "chatbox.projects"
    private let gptPresetsKey = "chatbox.gptPresets"

    func getLibraryItems() -> [LibraryItem] {
        decode([LibraryItem].self, forKey: libraryKey) ?? []
    }

    func saveLibraryItems(_ items: [LibraryItem]) {
        encode(items, forKey: libraryKey)
    }

    func getProjects() -> [ProjectFolder] {
        decode([ProjectFolder].self, forKey: projectsKey) ?? []
    }

    func saveProjects(_ projects: [ProjectFolder]) {
        encode(projects, forKey: projectsKey)
    }

    func getGPTPresets() -> [CustomGPTPreset] {
        decode([CustomGPTPreset].self, forKey: gptPresetsKey) ?? []
    }

    func saveGPTPresets(_ presets: [CustomGPTPreset]) {
        encode(presets, forKey: gptPresetsKey)
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
