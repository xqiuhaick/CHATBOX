import AppKit
import SwiftUI

extension Notification.Name {
    /// 仅在用户点击 Dock 且没有可见窗口时发送一次
    static let showMainWindow = Notification.Name("ChatBoxes.ShowMainWindow")
}

@MainActor
enum AppWindowController {
    static func bringMainWindowsForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        for window in NSApp.windows where window.canBecomeMain && !isSettingsWindow(window) {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.setIsVisible(true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.title.localizedCaseInsensitiveContains("设置")
            || window.title.localizedCaseInsensitiveContains("Settings")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 等 SwiftUI 创建完 WindowGroup 后再前置，避免与 openWindow 互相触发死循环
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            AppWindowController.bringMainWindowsForward()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            AppWindowController.bringMainWindowsForward()
        } else {
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

/// Dock 无窗口时由 SwiftUI 打开新主窗口（只响应通知，不再回调 activate）
struct MainWindowOpener: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
            openWindow(id: "main")
        }
    }
}

extension View {
    func handlesMainWindowReopen() -> some View {
        modifier(MainWindowOpener())
    }
}
