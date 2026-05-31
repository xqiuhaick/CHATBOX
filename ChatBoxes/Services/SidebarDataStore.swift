import Foundation
import Observation

struct LibraryItem: Identifiable, Codable, Equatable {
    let id: String
    var title: String
    var content: String
    let createdAt: TimeInterval
}

struct ProjectFolder: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var sessionIDs: [String]
    let createdAt: TimeInterval
}

struct CustomGPTPreset: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var icon: String
    var instructions: String
    var provider: String
    var model: String
    let createdAt: TimeInterval
}

@MainActor
@Observable
final class SidebarDataStore {
    static let shared = SidebarDataStore()

    var libraryItems: [LibraryItem] = []
    var projects: [ProjectFolder] = []
    var gptPresets: [CustomGPTPreset] = []

    private let storage = StorageService.shared

    init() {
        load()
    }

    func load() {
        libraryItems = storage.getLibraryItems()
        projects = storage.getProjects()
        gptPresets = storage.getGPTPresets()
        if gptPresets.isEmpty {
            gptPresets = defaultGPTPresets()
            saveGPTPresets()
        }
    }

    func addLibraryItem(title: String, content: String) {
        let item = LibraryItem(
            id: generateID(prefix: "lib"),
            title: title,
            content: content,
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        libraryItems.insert(item, at: 0)
        storage.saveLibraryItems(libraryItems)
    }

    func deleteLibraryItem(_ id: String) {
        libraryItems.removeAll { $0.id == id }
        storage.saveLibraryItems(libraryItems)
    }

    func addProject(name: String) {
        let project = ProjectFolder(
            id: generateID(prefix: "proj"),
            name: name,
            sessionIDs: [],
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        projects.insert(project, at: 0)
        storage.saveProjects(projects)
    }

    func addSession(_ sessionID: String, to projectID: String) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        if !projects[index].sessionIDs.contains(sessionID) {
            projects[index].sessionIDs.append(sessionID)
            storage.saveProjects(projects)
        }
    }

    func deleteProject(_ id: String) {
        projects.removeAll { $0.id == id }
        storage.saveProjects(projects)
    }

    func addGPTPreset(name: String, icon: String, instructions: String, provider: String, model: String) {
        let preset = CustomGPTPreset(
            id: generateID(prefix: "gpt"),
            name: name,
            icon: icon,
            instructions: instructions,
            provider: provider,
            model: model,
            createdAt: Date().timeIntervalSince1970 * 1000
        )
        gptPresets.insert(preset, at: 0)
        storage.saveGPTPresets(gptPresets)
    }

    func deleteGPTPreset(_ id: String) {
        gptPresets.removeAll { $0.id == id }
        storage.saveGPTPresets(gptPresets)
    }

    private func defaultGPTPresets() -> [CustomGPTPreset] {
        [
            CustomGPTPreset(
                id: "gpt_default_coding",
                name: "编程助手",
                icon: "chevron.left.forwardslash.chevron.right",
                instructions: "你是专业编程助手，回答简洁、准确，优先给出可运行代码。",
                provider: "deepseek",
                model: "deepseek-chat",
                createdAt: Date().timeIntervalSince1970 * 1000
            ),
            CustomGPTPreset(
                id: "gpt_default_writing",
                name: "写作助手",
                icon: "pencil.line",
                instructions: "你是专业写作助手，帮助润色、扩写、改写文本，保持自然流畅。",
                provider: "deepseek",
                model: "deepseek-chat",
                createdAt: Date().timeIntervalSince1970 * 1000
            )
        ]
    }

    private func saveGPTPresets() {
        storage.saveGPTPresets(gptPresets)
    }
}
