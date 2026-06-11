import UIKit
import Combine

/// QA 问答状态
enum QAState {
    case idle           // 空闲
    case scanning       // 扫描中
    case pointing       // 指向中
    case capturing      // 采集中
    case listening      // 等待语音输入
    case thinking       // AI 思考中
    case speaking       // TTS 播报中
}

/// QA 问答服务 - 完整的问答流程管理
class QAService: NSObject {

    // MARK: - 单例
    static let shared = QAService()

    // MARK: - 属性

    private let apiClient = APIClient.shared
    private let voiceService = VoiceService.shared
    private let speechService = VoiceService()
    private var webSocketClient: QAWebSocketClient?

    private var currentImage: UIImage?
    private var currentSessionId: String?
    private var conversationHistory: [[String: String]] = []
    private var isActive = false

    // 流式响应状态
    private var currentAnswerBuffer = ""
    private var isStreamingResponse = false
    private var autoDismissTimer: Timer?

    // MARK: - 状态

    private(set) var state: QAState = .idle {
        didSet {
            notifyStateChange()
        }
    }

    // MARK: - 回调

    var onAnswerReady: ((String) -> Void)?
    var onPartialAnswer: ((String) -> Void)?
    var onThinkingStarted: (() -> Void)?
    var onThinkingEnded: (() -> Void)?
    var onStateChanged: ((QAState) -> Void)?

    // MARK: - 初始化

    private override init() {
        super.init()
        setupVoiceCallbacks()
        setupGestureCallbacks()
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

    private func setupGestureCallbacks() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleGestureDetected(_:)),
            name: .gestureDetected,
            object: nil
        )
    }

    @objc private func handleGestureDetected(_ notification: Notification) {
        guard isActive else { return }

        if let gesture = notification.userInfo?["gesture"] as? GestureService.GestureType {
            switch gesture {
            case .ok:
                // OK 手势 - 打断当前流程
                interrupt()

            case .peace:
                // Peace 手势 - 结束当前轮次
                endRound()

            case .pointing:
                // 指向手势 - 可能触发问答
                handlePointingGesture()

            default:
                break
            }
        }
    }

    // MARK: - 状态转换

    func transitionTo(_ newState: QAState) {
        state = newState
    }

    private func notifyStateChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 发送通知
            NotificationCenter.default.post(
                name: .qaStateChanged,
                object: nil,
                userInfo: ["state": self.state]
            )

            // 回调
            self.onStateChanged?(self.state)
        }
    }

    // MARK: - 设置当前数据

    func setCurrentImage(_ image: UIImage) {
        currentImage = image
    }

    func setCurrentSession(_ sessionId: String) {
        currentSessionId = sessionId
        connectWebSocket(sessionId: sessionId)
    }

    // MARK: - WebSocket 连接

    private func connectWebSocket(sessionId: String) {
        webSocketClient?.disconnect()
        webSocketClient = QAWebSocketClient()
        webSocketClient?.delegate = self
        webSocketClient?.connect(sessionId: sessionId)
    }

    // MARK: - 问答流程

    func startRound() {
        isActive = true
        state = .scanning

        // 通知 UI 进入扫描状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.state = .listening
            self?.startListening()
        }
    }

    private func startListening() {
        // TTS 播报 "请说"
        speechService.speak("请说")

        // 延迟打开麦克风
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.state = .listening
            self?.speechService.startListening()
        }
    }

    private var pendingQuery: String?

    private func handleVoiceInput(_ text: String) {
        pendingQuery = text
        speechService.resetSilenceTimer()
    }

    private func checkAndProcessInput() {
        guard isActive else { return }

        guard let query = pendingQuery, !query.isEmpty else {
            // 没有输入，返回聆听状态
            state = .listening
            return
        }

        pendingQuery = nil

        // TTS 播报 "好的"
        speechService.speak("好的")

        // 开始思考
        state = .thinking
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

        // 尝试使用 WebSocket 流式响应
        if webSocketClient != nil {
            await processStreamingQuery(query, imageBase64: imageBase64)
        } else {
            // 回退到普通 API
            await processNormalQuery(query, imageBase64: imageBase64)
        }
    }

    /// 使用 WebSocket 流式响应
    private func processStreamingQuery(_ query: String, imageBase64: String?) async {
        isStreamingResponse = true
        currentAnswerBuffer = ""

        // 通过 WebSocket 发送查询
        webSocketClient?.sendQuery(query, imageBase64: imageBase64)

        // 注意：响应会通过 WebSocket 回调接收
        // 等待完成或超时
        await withCheckedContinuation { continuation in
            // 在 streamingResponseCompleted 中调用 continuation.resume()
            DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
                if self?.isStreamingResponse == true {
                    self?.isStreamingResponse = false
                    continuation.resume()
                }
            }
        }
    }

    /// 普通 API 响应
    private func processNormalQuery(_ query: String, imageBase64: String?) async {
        let request = QARequest(
            query: query,
            imageBase64: imageBase64,
            context: buildContext(),
            sessionId: currentSessionId,
            studentGoal: nil
        )

        do {
            let response = try await apiClient.askQuestion(request)
            await handleAnswerResponse(response.answer)

        } catch {
            await MainActor.run {
                onThinkingEnded?()
                speechService.speak("抱歉，发生了错误")
            }
        }
    }

    /// 处理答案响应
    private func handleAnswerResponse(_ answer: String) async {
        // 添加到对话历史
        conversationHistory.append(["role": "assistant", "content": answer])

        await MainActor.run {
            // 通知思考结束
            onThinkingEnded?()
            state = .speaking
            onAnswerReady?(answer)

            // TTS 播报答案
            Task {
                await speakAnswer(answer)
            }

            // 15秒后自动消失
            scheduleAutoDismiss()
        }
    }

    /// 处理流式响应片段
    private func handleStreamingPartial(_ content: String) {
        currentAnswerBuffer += content

        DispatchQueue.main.async { [weak self] in
            self?.onPartialAnswer?(self?.currentAnswerBuffer ?? "")
        }
    }

    /// 处理流式响应完成
    private func handleStreamingComplete(_ content: String) {
        isStreamingResponse = false

        let finalAnswer = content.isEmpty ? currentAnswerBuffer : content
        currentAnswerBuffer = ""

        Task {
            await handleAnswerResponse(finalAnswer)
        }
    }

    // MARK: - 打断和继续

    func interrupt() {
        guard isActive else { return }

        // 停止当前所有操作
        speechService.stopSpeaking()

        if isStreamingResponse {
            // 停止流式响应
            webSocketClient?.disconnect()
            isStreamingResponse = false
            currentAnswerBuffer = ""
        }

        // TTS 播报 "请说"
        speechService.speak("请说")

        // 重新开始聆听
        state = .listening

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.speechService.startListening()
        }
    }

    func endRound() {
        isActive = false
        currentImage = nil
        pendingQuery = nil
        currentAnswerBuffer = ""
        isStreamingResponse = false

        // 停止所有服务
        speechService.stopSpeaking()
        speechService.stopListening()
        webSocketClient?.disconnect()
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        // 状态转换
        state = .idle
    }

    // MARK: - 手势处理

    private func handlePointingGesture() {
        // 指向手势 - 可选：开始采集画面
        state = .capturing

        // 延迟返回聆听状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if self?.state == .capturing {
                self?.state = .listening
            }
        }
    }

    // MARK: - TTS 播报

    private func speakAnswer(_ answer: String) async {
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

    // MARK: - 自动消失

    private func scheduleAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.endRound()
        }
    }

    // MARK: - 辅助方法

    private func buildContext() -> String? {
        guard !conversationHistory.isEmpty else { return nil }

        var context = "对话历史:\n"
        for msg in conversationHistory {
            context += "[\(msg["role"] ?? "")]: \(msg["content"] ?? "")\n"
        }
        return context
    }

    // MARK: - 对话历史管理

    /// 获取对话历史
    func getConversationHistory() -> [[String: String]] {
        return conversationHistory
    }

    /// 清空对话历史
    func clearHistory() {
        conversationHistory = []
    }

    /// 删除最后一条消息
    func removeLastMessage() {
        if !conversationHistory.isEmpty {
            conversationHistory.removeLast()
        }
    }

    // MARK: - 发送查询（文本输入）

    func sendQuery(_ text: String) {
        handleVoiceInput(text)
        checkAndProcessInput()
    }

    // MARK: - 析构

    deinit {
        autoDismissTimer?.invalidate()
        webSocketClient?.disconnect()
    }
}

// MARK: - QAWebSocketClientDelegate

extension QAService: QAWebSocketClientDelegate {

    func webSocketDidConnect() {
        print("WebSocket connected")
    }

    func webSocketDidDisconnect(error: Error?) {
        print("WebSocket disconnected: \(error?.localizedDescription ?? "none")")

        // 如果是流式响应中断开，尝试使用普通 API
        if isStreamingResponse {
            isStreamingResponse = false
            // 可以在这里实现重试逻辑
        }
    }

    func webSocketDidReceivePartial(content: String) {
        handleStreamingPartial(content)
    }

    func webSocketDidReceiveComplete(content: String) {
        handleStreamingComplete(content)
    }

    func webSocketDidReceiveError(_ error: String) {
        print("WebSocket error: \(error)")

        // 尝试使用普通 API
        if isStreamingResponse, let query = pendingQuery {
            isStreamingResponse = false
            Task {
                await processNormalQuery(query, imageBase64: nil)
            }
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let qaStateChanged = Notification.Name("qaStateChanged")
}