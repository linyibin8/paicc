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
    let qaService = QAService()

    private override init() {
        super.init()
        setupCameraCallbacks()
        setupQACallbacks()
    }

    // MARK: - 相机设置

    func setupCamera(in view: UIView) {
        cameraService.setupCamera(in: view)
    }

    // MARK: - 扫描控制

    func startScanning() {
        guard scanState == .idle else { return }
        scanState = .scanning
        cameraService.startCapture()
        cameraService.enableGestureDetection()
    }

    func stopScanning() {
        cameraService.disableGestureDetection()
        cameraService.stopCapture()
        speechService.stopListening()
        scanState = .idle
    }

    // MARK: - 会话管理

    func createSession(studentGoal: String? = nil) async throws -> String {
        let sessionId = try await APIClient.shared.createSession(studentGoal: studentGoal)
        currentSessionId = sessionId
        qaService.setCurrentSession(sessionId)
        return sessionId
    }

    func endSession() async throws {
        guard let sessionId = currentSessionId else { return }
        try await APIClient.shared.endSession(sessionId: sessionId)
        currentSessionId = nil
    }

    // MARK: - 相机回调设置

    private func setupCameraCallbacks() {
        cameraService.onGestureDetected = { [weak self] gesture in
            self?.handleGestureDetected(gesture)
        }

        cameraService.onFrameCaptured = { [weak self] image in
            self?.qaService.setCurrentImage(image)
        }
    }

    // MARK: - QA 回调设置

    private func setupQACallbacks() {
        qaService.onStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .scanning, .listening:
                    self?.scanState = .scanning
                case .capturing, .thinking, .speaking:
                    self?.scanState = .qaActive
                case .pointing:
                    self?.scanState = .capturing
                case .interrupted:
                    self?.scanState = .scanning
                case .idle:
                    self?.scanState = .idle
                }
            }
        }

        qaService.onThinkingStarted = { [weak self] in
            // 播放思考音
            self?.speechService.playThinkingSound()
        }

        qaService.onAnswerReady = { [weak self] answer, _, _ in
            // 答案准备好的回调（已在 QAService 中处理 TTS）
            _ = answer
            _ = self
        }
    }

    // MARK: - 手势处理

    private func handleGestureDetected(_ gesture: GestureType) {
        switch gesture {
        case .pointing:
            // 指向手势 - 截取当前帧并开始问答
            scanState = .capturing
            if let image = cameraService.captureCurrentFrame() {
                qaService.setCurrentImage(image)
                // 启动问答流程
                qaService.startRound()
            }

        case .ok:
            // OK 手势 - 打断当前问答
            qaService.interrupt()

        case .peace:
            // ✌️ 手势 - 结束本轮问答
            qaService.endRound()

        case .raisedHand:
            // 举手 - 记录学生存在
            studentPresent = true
        }
    }

    // MARK: - 清理

    func cleanup() {
        stopScanning()
        qaService.endRound()
    }

    deinit {
        cleanup()
    }
}

// MARK: - 通知名称

extension Notification.Name {
    static let gestureDetected = Notification.Name("gestureDetected")
    static let speechResult = Notification.Name("speechResult")
    static let qaStateChanged = Notification.Name("qaStateChanged")
}