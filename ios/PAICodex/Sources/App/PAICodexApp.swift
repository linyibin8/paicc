//
//  PAI-CC iOS 主程序入口
//

import SwiftUI

@main
struct PAICodexApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App State
@MainActor
class AppState: ObservableObject {
    @Published var currentSession: Session?
    @Published var conversationState: ConversationState = .standby
    @Published var isListening: Bool = false
    @Published var lastRecognizedQuery: String = ""

    let cameraService = CameraService()
    let gestureService = GestureService()
    let speechService = SpeechService()
    let networkService = NetworkService()

    init() {
        setupServices()
    }

    private func setupServices() {
        // 初始化服务
        cameraService.startCapture()
        gestureService.startDetection()
        speechService.requestPermission()
    }
}

// MARK: - 对话状态
enum ConversationState: String {
    case standby = "待命"
    case listening = "倾听"
    case thinking = "思考"
    case speaking = "回答"
}

// MARK: - 会话模型
struct Session: Identifiable {
    let id: String
    var status: String = "created"
    var createdAt: Date = Date()
    var totalCaptures: Int = 0
}