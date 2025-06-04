💬 CHATBOX

CHATBOX 是一款基于 SwiftUI 构建的 macOS 原生 AI 聊天客户端，支持 OpenAI、硅基流动（DeepSeek）、Google Gemini 等主流大模型服务，界面简洁，交互顺畅，支持 Markdown、多会话、主题切换等功能。

✨ 功能亮点
	•	✅ 多模型接入：支持 OpenAI（GPT-4/4o）、DeepSeek R1/V3、Gemini 2.5 等主流模型。
	•	💬 多会话管理：支持会话列表管理、自动命名、删除会话等操作。
	•	🧠 模拟打字效果：逐字渲染 AI 回复，提供更沉浸的对话体验。
	•	🎨 原生暗黑/浅色主题支持：跟随系统或手动切换。
	•	📝 Markdown 支持：AI 回复支持 Markdown 格式，列表、加粗、代码块等都能正确显示。
	•	⚙️ 可配置 API Key 和 Endpoint：支持通过设置面板配置不同服务商的 Key 和 API 地址。
	•	💡 思考模式支持：对于 DeepSeek 模型启用“思考中…”进度提示。
	•	⌨️ 键盘友好体验：发送支持按下 Enter，自动聚焦输入框。

📸 界面预览

📦 支持的模型

提供商	模型示例	说明
OpenAI	gpt-4o, gpt-4.1	需要 OpenAI API Key
硅基流动	DeepSeek R1, DeepSeek V3	免费注册即可获取 API Key
Google Gemini	Gemini 2.5 Flash	需 Google Cloud API Key

🛠️ 构建方式

本项目基于 SwiftUI + Swift Concurrency 构建，运行环境为：
	•	macOS 13+
	•	Xcode 15+
	•	Swift 5.9+

依赖库

通过 Swift Package Manager 集成：
	•	MarkdownUI — 用于渲染 Markdown
	•	NetworkImage — （如需加载图片）

运行方式
	1.	克隆项目

git clone https://github.com/yourname/chatbox.git
cd chatbox
open CHATBOX.xcodeproj


	2.	在 Xcode 中运行 (Cmd + R)
	3.	首次使用请点击左下角 API设置，分别为不同服务商配置 Key 和可选 Endpoint。

📄 设置说明

设置面板支持以下项：
	•	API Key：用于认证各模型服务商
	•	API Endpoint（可选）：如使用代理或自建接口，可自定义 base URL

🧩 文件结构简述
	•	ContentView.swift：主界面视图与逻辑入口，集成了会话、输入区、消息列表。
	•	ChatViewModel.swift：负责处理消息状态与发送逻辑。
	•	ChatService.swift：封装对各模型 API 的请求与响应解析。
	•	ModelInfo.swift：定义模型结构和提供商信息。

🧪 后续规划
	•	支持多模态（图像/语音）输入
	•	自动保存消息历史
	•	导出对话内容
	•	本地离线模型集成（如 llama.cpp）

📝 License

MIT License

⸻

如果你希望我生成 .md 文件内容用于直接复制，或者想要包含徽标、Badge、截图占位图链接、使用 gif 预览等，也可以告诉我，我帮你完善。是否要继续输出成 markdown 文件格式？
