import UIKit
import Combine

/// QA 问答服务
class QAService {

    // MARK: - 属性
    private let apiClient = APIClient.shared
    private let voiceService = VoiceService.shared
    private let speechService = VoiceService()

    private var currentImage: UIImage?
    private var currentSessionId: String?
    private var conversationHistory: [[String: String]] = []
    private var isActive = false

    // MARK: - 回调

    var onAnswerReady: ((String) -> Void)?
    var onThinkingStarted: (() -> Void)?
    var onThinkingEnded: (() -> Void)?

    // MARK: - 初始化

    init() {
        setupVoiceCallbacks()
    }

    private func setupVoiceCallbacks() {
        speechService.onSpeechResult = { [weak self] text in
            self?.handleVoiceInput(text)
        }

        speechService.onListeningStateChanged = { [weak self] isListening in
            if !isListening {
                // 语音输入结束
                self?.checkAndProcessInput()
            }
        }
    }

    // MARK: - 设置当前图像

    func setCurrentImage(_ image: UIImage) {
        currentImage = image
    }

    func setCurrentSession(_ sessionId: String) {
        currentSessionId = sessionId
    }

    // MARK: - 问答流程

    func startRound() {
        isActive = true
        conversationHistory = []

        // 通知 UI 进入聆听状态
        notifyState("listening")

        // TTS 播报 "请说"
        speechService.speak("请说")

        // 延迟打开麦克风
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.speechService.startListening()
        }
    }

    private var pendingQuery: String?

    private func handleVoiceInput(_ text: String) {
        pendingQuery = text
        speechService.resetSilenceTimer()
    }

    private func checkAndProcessInput() {
        guard let query = pendingQuery, !query.isEmpty else {
            // 没有输入，返回聆听状态
            return
        }

        pendingQuery = nil

        // TTS 播报 "好的"
        speechService.speak("好的")

        // 开始思考
        notifyState("thinking")
        onThinkingStarted?()

        // 处理问答
        Task {
            await processQuery(query)
        }
    }

    private func processQuery(_ query: String) async {
        // 添加到对话历史
        conversationHistory.append(["role": "user", "content": query])

        // 准备图像数据
        var imageBase64: String?
        if let image = currentImage,
           let imageData = image.jpegData(compressionQuality: 0.6) {
            imageBase64 = imageData.base64EncodedString()
        }

        // 构建请求
        let request = QARequest(
            query: query,
            imageBase64: imageBase64,
            context: buildContext(),
            sessionId: currentSessionId,
            studentGoal: nil
        )

        do {
            let response = try await apiClient.askQuestion(request)

            // 添加到对话历史
            conversationHistory.append(["role": "assistant", "content": response.answer])

            // 通知思考结束
            DispatchQueue.main.async { [weak self] in
                self?.onThinkingEnded?()
                self?.notifyState("speaking")
                self?.onAnswerReady?(response.answer)
            }

            // TTS 播报答案
            await speakAnswer(response.answer)

            // 15秒后自动消失
            DispatchQueue.main.asyncAfter(deadline: .now() + 15.0) { [weak self] in
                self?.endRound()
            }

        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onThinkingEnded?()
                self?.speechService.speak("抱歉，发生了错误")
            }
        }
    }

    // MARK: - 打断和结束

    func interrupt() {
        // 停止思考音
        speechService.stopSpeaking()

        // TTS 播报 "请说"
        speechService.speak("请说")

        // 重新开始聆听
        speechService.startListening()
        notifyState("listening")
    }

    func endRound() {
        isActive = false
        currentImage = nil
        pendingQuery = nil

        speechService.stopSpeaking()
        speechService.stopListening()

        notifyState("idle")
    }

    // MARK: - TTS 播报

    private func speakAnswer(_ answer: String) async {
        // 使用 TTS 服务获取音频
        do {
            #if DEBUG
            let ttsEndpoint = APIConfig.localTTSURL + "/synthesize"
            #else
            let ttsEndpoint = APIConfig.ttsURL + "/synthesize"
            #endif
            let audioData = try await apiClient.synthesize(text: answer, voice: "zh-CN")
            speechService.playAudioData(audioData)
        } catch {
            // 回退到系统 TTS
            speechService.speak(answer)
        }
    }

    // MARK: - 辅助方法

    private func buildContext() -> String? {
        // 从对话历史构建上下文
        guard !conversationHistory.isEmpty else { return nil }

        var context = "对话历史:\n"
        for msg in conversationHistory {
            context += "[\(msg["role"] ?? "")]: \(msg["content"] ?? "")\n"
        }
        return context
    }

    private func notifyState(_ state: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .qaStateChanged,
                object: nil,
                userInfo: ["state": state]
            )
        }
    }

    // MARK: - 发送查询

    func sendQuery(_ text: String) {
        handleVoiceInput(text)
        checkAndProcessInput()
    }
}