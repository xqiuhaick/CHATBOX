import SwiftUI

@main
struct ChatBoxesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ChatStore()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(store)
                .environment(\.glassIntensity, store.settings.glassIntensity)
                .preferredColorScheme(preferredColorScheme)
                .handlesMainWindowReopen()
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新对话") {
                    store.createAndSelectSession()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(\.glassIntensity, store.settings.glassIntensity)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 520, height: 640)
    }

    private var preferredColorScheme: ColorScheme? {
        switch store.settings.appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
