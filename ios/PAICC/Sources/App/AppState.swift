import Foundation
import UIKit
import AVFoundation
import Speech
import Vision
import Combine

/// PAI-CC 全局应用状态管理
class AppState: NSObject {
    static let shared = AppState()

    // MARK: - 状态
    enum ScanState {
        case idle
        case scanning
        case capturing
        case analyzing
        case qaActive
    }

    @Published var scanState: ScanState = .idle
    @Published var currentSessionId: String?
    @Published var lastCaptureTime: Date?
    @Published var studentPresent: Bool = false

    // MARK: - 服务
    let cameraService = CameraService()
    let speechService = VoiceService.shared
    let gestureService = GestureService()
    let apiClient = APIClient.shared
    let qaService = QAService()

    private override init() {
        super.init()
        setupNotifications()
    }

    // MARK: - 扫描控制

    func startScanning() {
        guard scanState == .idle else { return }
        scanState = .scanning
        cameraService.startCapture()
        gestureService.startDetection()
    }

    func stopScanning() {
        scanState = .idle
        cameraService.stopCapture()
        gestureService.stopDetection()
        speechService.stopListening()
    }

    // MARK: - 会话管理

    func createSession(studentGoal: String? = nil) async throws -> String {
        let sessionId = try await apiClient.createSession(studentGoal: studentGoal)
        currentSessionId = sessionId
        return sessionId
    }

    func endSession() async throws {
        guard let sessionId = currentSessionId else { return }
        try await apiClient.endSession(sessionId: sessionId)
        currentSessionId = nil
    }

    // MARK: - 通知

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGestureDetected(_:)),
            name: .gestureDetected,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSpeechResult(_:)),
            name: .speechResult,
            object: nil
        )
    }

    @objc private func handleGestureDetected(_ notification: Notification) {
        guard let gesture = notification.userInfo?["gesture"] as? GestureService.GestureType else { return }

        if gesture == .pointing {
            // 检测到指向手势，截取当前帧
            captureCurrentFrame()
        } else if gesture == .ok {
            // OK 手势，打断当前问答
            qaService.interrupt()
        } else if gesture == .peace {
            // ✌️ 手势，结束本轮问答
            qaService.endRound()
        }
    }

    @objc private func handleSpeechResult(_ notification: Notification) {
        guard let text = notification.userInfo?["text"] as? String else { return }
        qaService.sendQuery(text)
    }

    private func captureCurrentFrame() {
        scanState = .capturing
        if let image = cameraService.captureCurrentFrame() {
            qaService.setCurrentImage(image)
        }
        scanState = .scanning
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let gestureDetected = Notification.Name("gestureDetected")
    static let speechResult = Notification.Name("speechResult")
    static let qaStateChanged = Notification.Name("qaStateChanged")
}