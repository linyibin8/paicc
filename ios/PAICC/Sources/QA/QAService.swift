import UIKit
import Combine

// MARK: - 枚举定义

/// QA 问答状态
enum QAState {
    case idle           // 空闲
    case scanning       // 扫描中
    case pointing       // 指向中
    case capturing      // 采集中
    case listening      // 等待语音输入
    case thinking       // AI 思考中
    case speaking       // TTS 播报中
    case interrupted    // 已打断
}

/// 流式消息类型
enum QAStreamMessageType: String {
    case thinking = "thinking"
    case partial = "partial"
    case answer = "answer"
    case error = "error"
    case interrupted = "interrupted"
    case ttsStart = "tts_start"
    case ttsReady = "tts_ready"
    case ttsError = "tts_error"
    case historyUpdate = "history_update"
    case cleared = "cleared"
    case pong = "pong"
}

/// 触发类型
enum QATriggerType: String {
    case voice = "voice"
    case gesture = "gesture"
    case auto = "auto"
}

// MARK: - 数据模型

/// 对话历史消息
struct QAHistoryMessage: Codable {
    let role: String          // user, assistant, system
    let content: String
    let timestamp: String?
    let metadata: [String: String]?

    init(role: String, content: String, metadata: [String: String]? = nil) {
        self.role = role
        self.content = content
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.metadata = metadata
    }
}

/// 知识要点
struct QAKnowledgePoint: Codable {
    let point: String
    let category: String?
}

/// 建议的后续问题
struct QASuggestedFollowup: Codable {
    let question: String
    let type: String?
}

// MARK: - QA 问答服务

/// QA 问答服务 - 完整的问答流程管理
class QAService: NSObject {

    // MARK: - 常量

    private let maxHistoryCount = 20  // 最大历史条数
    private let maxContextMessages = 10  // 最大上下文消息数（不含系统提示）

    // MARK: - 单例

    static let shared = QAService()

    // MARK: - 属性

    private let apiClient = APIClient.shared
    private let voiceService = VoiceService.shared
    private var webSocketClient: QAWebSocketClient?

    private var currentImage: UIImage?
    private var currentSessionId: String?
    private var conversationHistory: [QAHistoryMessage] = []
    private var isActive = false

    // 流式响应状态
    private var currentAnswerBuffer = ""
    private var isStreamingResponse = false
    private var autoDismissTimer: Timer?

    // 打断状态
    private var isInterrupted = false
    private var pendingQuery: String?
    private var pendingImageBase64: String?

    // Vision 能力缓存
    private var visionSupported: Bool? = nil

    // MARK: - 状态

    private(set) var state: QAState = .idle {
        didSet {
            notifyStateChange()
        }
    }

    // MARK: - 回调

    var onAnswerReady: ((String, [QAKnowledgePoint], [QASuggestedFollowup]) -> Void)?
    var onPartialAnswer: ((String) -> Void)?
    var onThinkingStarted: (() -> Void)?
    var onThinkingEnded: (() -> Void)?
    var onStateChanged: ((QAState) -> Void)?
    var onInterrupted: (() -> Void)?
    var onHistoryUpdated: (([QAHistoryMessage]) -> Void)?
    var onTTSReady: ((String) -> Void)?  // audio_url

    // MARK: - 初始化

    override init() {
        super.init()
        setupVoiceCallbacks()
        setupGestureCallbacks()
    }

    private func setupVoiceCallbacks() {
        voiceService.onSpeechResult = { [weak self] text, _ in
            self?.handleVoiceInput(text)
        }

        voiceService.onListeningStateChanged = { [weak self] isListening in
            if !isListening {
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

        if let gesture = notification.userInfo?["gesture"] as? GestureType {
            switch gesture {
            case .ok:
                interrupt()

            case .peace:
                endRound()

            case .pointing:
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

            NotificationCenter.default.post(
                name: .qaStateChanged,
                object: nil,
                userInfo: ["state": self.state]
            )

            self.onStateChanged?(self.state)
        }
    }

    // MARK: - 设置当前数据

    func setCurrentImage(_ image: UIImage) {
        currentImage = image
    }

    func setCurrentSession(_ sessionId: String) {
        // 清空旧的历史
        clearHistory()
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.state = .listening
            self?.startListening()
        }
    }

    private func startListening() {
        voiceService.speak("请说")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.state = .listening
            self?.voiceService.startListening()
        }
    }

    private func handleVoiceInput(_ text: String) {
        pendingQuery = text
        voiceService.resetSilenceTimer()
    }

    private func checkAndProcessInput() {
        guard isActive else { return }

        guard let query = pendingQuery, !query.isEmpty else {
            state = .listening
            return
        }

        pendingQuery = nil

        voiceService.speak("好的")

        state = .thinking
        onThinkingStarted?()

        Task {
            await processQuery(query)
        }
    }

    // MARK: - 处理查询

    private func processQuery(_ query: String) async {
        // 添加到对话历史
        addToHistory(role: "user", content: query, metadata: ["trigger": "voice"])

        // 准备图像数据
        var imageBase64: String?
        if let image = currentImage,
           let imageData = image.jpegData(compressionQuality: 0.6) {
            imageBase64 = imageData.base64EncodedString()
        }

        // 保存待处理的数据（用于打断后恢复）
        pendingQuery = query
        pendingImageBase64 = imageBase64

        // 使用 WebSocket 流式响应
        if webSocketClient != nil {
            await processStreamingQuery(query, imageBase64: imageBase64)
        } else {
            await processNormalQuery(query, imageBase64: imageBase64)
        }
    }

    /// 使用 WebSocket 流式响应
    private func processStreamingQuery(_ query: String, imageBase64: String?) async {
        isStreamingResponse = true
        currentAnswerBuffer = ""
        isInterrupted = false

        // 通过 WebSocket 发送查询
        webSocketClient?.sendQuery(
            query,
            imageBase64: imageBase64,
            enableTTS: true,
            history: getHistoryForRequest()
        )

        // 等待完成或打断
        await withCheckedContinuation { continuation in
            // 在 streamingResponseCompleted 或 interrupt 中调用 continuation.resume()
            DispatchQueue.main.asyncAfter(deadline: .now() + 60.0) { [weak self] in
                if self?.isStreamingResponse == true {
                    self?.isStreamingResponse = false
                    continuation.resume()
                }
            }
        }
    }

    /// 普通 API 响应（回退方案）
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
                voiceService.speak("抱歉，发生了错误")
            }
        }
    }

    // MARK: - 处理答案响应

    private func handleAnswerResponse(_ answer: String) async {
        // 添加到对话历史
        addToHistory(role: "assistant", content: answer)

        await MainActor.run {
            onThinkingEnded?()
            state = .speaking

            // 提取知识要点和后续建议
            let knowledgePoints = extractKnowledgePoints(from: answer)
            let suggestedFollowups = extractSuggestedFollowups(from: answer)

            onAnswerReady?(answer, knowledgePoints, suggestedFollowups)

            Task {
                await speakAnswer(answer)
            }

            scheduleAutoDismiss()
        }
    }

    /// 处理流式响应片段
    private func handleStreamingPartial(_ content: String) {
        // 检查是否被打断
        if isInterrupted {
            return
        }

        currentAnswerBuffer += content

        DispatchQueue.main.async { [weak self] in
            self?.onPartialAnswer?(self?.currentAnswerBuffer ?? "")
        }
    }

    /// 处理流式响应完成
    private func handleStreamingComplete(_ content: String, knowledgePoints: [String], suggestedFollowups: [String]) {
        isStreamingResponse = false

        let finalAnswer = content.isEmpty ? currentAnswerBuffer : content
        currentAnswerBuffer = ""

        Task {
            await handleAnswerResponse(finalAnswer)
        }
    }

    // MARK: - 打断和继续

    /// 打断当前流程
    func interrupt() {
        guard isActive else { return }

        isInterrupted = true

        // 停止当前所有操作
        voiceService.stopSpeaking()

        if isStreamingResponse {
            // 通知 WebSocket 打断
            webSocketClient?.sendInterrupt()
            isStreamingResponse = false
            currentAnswerBuffer = ""
        }

        state = .interrupted
        onInterrupted?()

        // TTS 播报 "请说"
        voiceService.speak("请说")

        // 重新开始聆听
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.state = .listening
            self?.voiceService.startListening()
        }
    }

    /// 追问 - 在当前回答后继续提问
    func followUp(with query: String) {
        guard isActive else { return }

        // 如果正在播报，打断后开始追问
        if state == .speaking {
            voiceService.stopSpeaking()
        }

        // 直接处理追问
        pendingQuery = query
        state = .thinking
        onThinkingStarted?()

        Task {
            await processQuery(query)
        }
    }

    /// 重新开始当前回答
    func replayAnswer() {
        guard !currentAnswerBuffer.isEmpty || !conversationHistory.isEmpty else { return }

        // 获取最后一个 AI 回答
        if let lastAssistantMessage = conversationHistory.last(where: { $0.role == "assistant" }) {
            voiceService.stopSpeaking()
            state = .speaking
            Task {
                await speakAnswer(lastAssistantMessage.content)
            }
        }
    }

    /// 结束当前轮次
    func endRound() {
        isActive = false
        currentImage = nil
        pendingQuery = nil
        pendingImageBase64 = nil
        currentAnswerBuffer = ""
        isStreamingResponse = false
        isInterrupted = false

        voiceService.stopSpeaking()
        voiceService.stopListening()
        webSocketClient?.disconnect()
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        state = .idle
    }

    // MARK: - 手势处理

    private func handlePointingGesture() {
        state = .capturing

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
            voiceService.playAudioData(audioData)
        } catch {
            voiceService.speak(answer)
        }
    }

    // MARK: - 自动消失

    private func scheduleAutoDismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.endRound()
        }
    }

    // MARK: - 上下文构建

    /// 构建发送给 API 的上下文信息
    private func buildContext() -> String? {
        guard !conversationHistory.isEmpty else { return nil }

        var context = "对话历史:\n"
        for msg in conversationHistory {
            context += "[\(msg.role)]: \(msg.content)\n"
        }
        return context
    }

    /// 获取用于请求的历史记录（最近 N 条）
    private func getHistoryForRequest() -> [[String: String]] {
        return conversationHistory
            .suffix(maxContextMessages)
            .map { ["role": $0.role, "content": $0.content] }
    }

    // MARK: - 对话历史管理

    /// 添加到对话历史
    private func addToHistory(role: String, content: String, metadata: [String: String]? = nil) {
        let message = QAHistoryMessage(role: role, content: content, metadata: metadata)
        conversationHistory.append(message)

        // 保持最近 maxHistoryCount 条
        if conversationHistory.count > maxHistoryCount {
            conversationHistory.removeFirst(conversationHistory.count - maxHistoryCount)
        }

        // 通知历史更新
        onHistoryUpdated?(conversationHistory)
    }

    /// 获取对话历史
    func getConversationHistory() -> [QAHistoryMessage] {
        return conversationHistory
    }

    /// 获取对话历史（字典格式，用于 API 请求）
    func getConversationHistoryDict() -> [[String: String]] {
        return conversationHistory.map { ["role": $0.role, "content": $0.content] }
    }

    /// 清空对话历史
    func clearHistory() {
        conversationHistory = []
        onHistoryUpdated?(conversationHistory)

        // 通知 WebSocket 清空
        webSocketClient?.sendClear()
    }

    /// 删除最后一条消息
    func removeLastMessage() {
        if !conversationHistory.isEmpty {
            conversationHistory.removeLast()
            onHistoryUpdated?(conversationHistory)
        }
    }

    /// 获取历史条数
    func getHistoryCount() -> Int {
        return conversationHistory.count
    }

    // MARK: - 知识提取

    private func extractKnowledgePoints(from text: String) -> [QAKnowledgePoint] {
        var points: [QAKnowledgePoint] = []

        // 提取 📚 知识点 后的内容
        let patterns = [
            "📚\\s*知识点[：:]?\\s*(.+?)(?=\\n|$)",
            "涉及[的]?\\s*(.+?知识点.+?)(?=\\n|$)",
            "[-*]\\s*(.+?知识点.+?)(?=\\n|$)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                let matches = regex.matches(in: text, options: [], range: range)
                for match in matches {
                    if let contentRange = Range(match.range(at: 1), in: text) {
                        let content = String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !content.isEmpty {
                            points.append(QAKnowledgePoint(point: content, category: nil))
                        }
                    }
                }
            }
        }

        // 去重并限制数量
        let uniquePoints = Array(Set(points.map { $0.point })).prefix(5)
        return uniquePoints.map { QAKnowledgePoint(point: $0, category: nil) }
    }

    private func extractSuggestedFollowups(from text: String) -> [QASuggestedFollowup] {
        var suggestions: [QASuggestedFollowup] = []

        let keywords = ["详细解释", "举一反三", "换一道题", "下一题", "继续"]
        for keyword in keywords {
            if text.contains(keyword) {
                suggestions.append(QASuggestedFollowup(question: keyword, type: "quick_action"))
            }
        }

        // 如果没有找到，添加默认建议
        if suggestions.isEmpty {
            suggestions = [
                QASuggestedFollowup(question: "详细解释", type: "clarify"),
                QASuggestedFollowup(question: "举一反三", type: "practice"),
                QASuggestedFollowup(question: "换一道题", type: "next")
            ]
        }

        return suggestions
    }

    // MARK: - 发送查询（文本输入）

    func sendQuery(_ text: String) {
        handleVoiceInput(text)
        checkAndProcessInput()
    }

    /// 直接发送文本查询（不通过语音）
    func sendTextQuery(_ text: String, withImage: Bool = true) {
        guard !text.isEmpty else { return }

        isActive = true
        state = .thinking
        onThinkingStarted?()

        Task {
            await processQuery(text)
        }
    }

    // MARK: - WebSocket 消息发送

    /// 发送追问
    func sendFollowUp(_ query: String) {
        followUp(with: query)
    }

    /// 请求获取历史
    func requestHistory() {
        webSocketClient?.sendGetHistory()
    }

    /// 发送心跳
    func sendPing() {
        webSocketClient?.sendPing()
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
        print("QA WebSocket connected")
        // 连接成功后请求历史
        requestHistory()
    }

    func webSocketDidDisconnect(error: Error?) {
        print("QA WebSocket disconnected: \(error?.localizedDescription ?? "none")")

        if isStreamingResponse {
            isStreamingResponse = false
        }
    }

    func webSocketDidReceiveMessage(_ message: [String: Any]) {
        guard let typeString = message["type"] as? String,
              let messageType = QAStreamMessageType(rawValue: typeString) else {
            return
        }

        switch messageType {
        case .thinking:
            // AI 正在思考
            DispatchQueue.main.async { [weak self] in
                if self?.state != .thinking {
                    self?.state = .thinking
                    self?.onThinkingStarted?()
                }
            }

        case .partial:
            // 流式片段
            if let content = message["content"] as? String {
                handleStreamingPartial(content)
            }

        case .answer:
            // 完整回答
            let content = message["content"] as? String ?? ""
            let knowledgePoints = (message["knowledge_points"] as? [String]) ?? []
            let suggestedFollowups = (message["suggested_followups"] as? [String]) ?? []
            handleStreamingComplete(content, knowledgePoints: knowledgePoints, suggestedFollowups: suggestedFollowups)

        case .error:
            // 错误
            let errorContent = message["content"] as? String ?? "未知错误"
            print("QA WebSocket error: \(errorContent)")

            if isStreamingResponse {
                isStreamingResponse = false
                // 尝试使用普通 API
                if let query = pendingQuery {
                    Task {
                        await processNormalQuery(query, imageBase64: pendingImageBase64)
                    }
                }
            }

        case .interrupted:
            // 被打断
            isInterrupted = true
            isStreamingResponse = false

            DispatchQueue.main.async { [weak self] in
                self?.state = .interrupted
                self?.onInterrupted?()
            }

        case .ttsStart:
            // TTS 开始生成
            print("TTS processing...")

        case .ttsReady:
            // TTS 生成完成
            if let audioUrl = message["audio_url"] as? String {
                DispatchQueue.main.async { [weak self] in
                    self?.onTTSReady?(audioUrl)
                }
            }

        case .ttsError:
            // TTS 错误
            print("TTS error: \(message["error"] as? String ?? "unknown")")

        case .historyUpdate:
            // 历史更新
            if let history = message["history"] as? [[String: String]] {
                // 同步历史（如果需要）
                print("History updated: \(history.count) messages")
            }

        case .cleared:
            // 历史已清空
            conversationHistory = []
            DispatchQueue.main.async { [weak self] in
                self?.onHistoryUpdated?(self?.conversationHistory ?? [])
            }

        case .pong:
            // 心跳响应
            break
        }
    }

    func webSocketDidReceiveError(_ error: String) {
        print("QA WebSocket error: \(error)")

        if isStreamingResponse {
            isStreamingResponse = false
            if let query = pendingQuery {
                Task {
                    await processNormalQuery(query, imageBase64: pendingImageBase64)
                }
            }
        }
    }
}

// MARK: - Notification Extension

// 注意: Notification.Name 扩展已在 AppState.swift 中定义
// MARK: - 缺失的 delegate 方法

extension QAService {
    
    /// 处理部分响应（打字机效果）
    func webSocketDidReceivePartial(_ client: QAWebSocketClient, content: String, isFirst: Bool) {
        // 使用现有的流式处理方法
        handleStreamingPartial(content)
        
        // 如果是第一个片段，通知 UI
        if isFirst {
            DispatchQueue.main.async {
                self.state = .thinking
            }
        }
    }
    
    /// 处理完整响应
    func webSocketDidReceiveComplete(_ client: QAWebSocketClient, content: String, knowledgePoints: [String]?, suggestions: [String]?) {
        // 使用现有的完整处理方法
        handleStreamingComplete(
            content,
            knowledgePoints: knowledgePoints ?? [],
            suggestedFollowups: suggestions ?? []
        )
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let qaStateChanged = Notification.Name("QAService.qaStateChanged")
}
