//
//  CHATBOXApp.swift
//  CHATBOX
//
//  Created by liruixiang on 2025/6/1.
//

//
//  CHATBOXApp.swift
//  CHATBOX
//
//  Created by liruixiang on 2025/6/1.
//

import SwiftUI

@main
struct CHATBOXApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light) // 默认使用浅色模式启动
        }
        .windowStyle(.hiddenTitleBar) // 隐藏标题栏，更接近ChatGPT应用风格
        .windowToolbarStyle(.unified) // 使用统一工具栏样式
    }
}
