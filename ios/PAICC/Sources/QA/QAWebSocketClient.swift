import Foundation


/// WebSocket 连接状态
enum WSConnectionState: String, Codable {
    case disconnected
    case connecting
    case connected
    case reconnecting
}

/// WebSocket 客户端错误
enum WSClientError: Error, LocalizedError {
    case invalidURL
    case connectionFailed
    case disconnected
    case sendFailed
    case invalidMessage
    case timeout
    case cancelled
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 WebSocket URL"
        case .connectionFailed:
            return "WebSocket 连接失败"
        case .disconnected:
            return "WebSocket 已断开"
        case .sendFailed:
            return "消息发送失败"
        case .invalidMessage:
            return "无效的消息格式"
        case .timeout:
            return "WebSocket 连接超时"
        case .cancelled:
            return "请求已取消"
        case .serverError(let message):
            return "服务器错误: \(message)"
        }
    }
}

/// WebSocket 客户端回调
protocol QAWebSocketClientDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceiveMessage(_ message: [String: Any])
    func webSocketDidReceiveError(_ error: String)
    
    // 流式响应回调
    func webSocketDidReceivePartial(_ client: QAWebSocketClient, content: String, isFirst: Bool)
    func webSocketDidReceiveComplete(_ client: QAWebSocketClient, content: String, knowledgePoints: [String]?, suggestions: [String]?)
}

/// QA WebSocket 客户端 - 处理流式问答
class QAWebSocketClient: NSObject {

    // MARK: - 属性

    weak var delegate: QAWebSocketClientDelegate?

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var isConnected = false
    private var currentSessionId: String?

    // 连接状态
    private(set) var connectionState: WSConnectionState = .disconnected

    // 重连配置
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 3
    private var reconnectTimer: Timer?

    // 心跳配置
    private var heartbeatTimer: Timer?
    private let heartbeatInterval: TimeInterval = 30.0
    private let heartbeatTimeout: TimeInterval = 10.0

    // 超时配置
    private var responseTimeout: TimeInterval = 60.0
    private var responseTimer: Timer?

    // 打断机制
    private var isCancelled = false
    private var pendingQuery: String?
    private var isWaitingForResponse = false

    // 缓冲
    private var contentBuffer = ""

    // 响应完成回调
    private var completionHandler: (() -> Void)?

    // MARK: - 初始化

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - 连接管理

    /// 连接到 WebSocket 服务器
    /// - Parameter sessionId: 会话 ID
    func connect(sessionId: String) {
        if isConnected || connectionState == .connecting {
            disconnect()
        }

        currentSessionId = sessionId
        connectionState = .connecting
        isCancelled = false

        guard let url = APIClient.shared.webSocketURL(sessionId: sessionId) else {
            delegate?.webSocketDidReceiveError("Invalid WebSocket URL")
            connectionState = .disconnected
            return
        }

        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessage()

        sendConnectionMessage()

        startConnectionTimeout()
    }

    /// 断开连接
    func disconnect() {
        stopTimers()
        isCancelled = true

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        connectionState = .disconnected

        isWaitingForResponse = false
        pendingQuery = nil
        contentBuffer = ""
    }

    /// 断开并清理
    func cleanup() {
        disconnect()
        currentSessionId = nil
        reconnectAttempts = 0
    }

    // MARK: - 打断机制

    /// 打断当前操作
    func interrupt() {
        guard isWaitingForResponse || !contentBuffer.isEmpty else {
            return
        }

        isCancelled = true
        isWaitingForResponse = false
        responseTimer?.invalidate()
        responseTimer = nil

        contentBuffer = ""

        sendInterruptSignal()

        delegate?.webSocketDidReceiveError("Interrupted by user")
    }

    /// 发送中断信号到服务器
    private func sendInterruptSignal() {
        guard isConnected else { return }

        let message: [String: Any] = [
            "type": "interrupt",
            "session_id": currentSessionId ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: data, encoding: .utf8) {
            send(jsonString)
        }
    }

    /// 取消并准备新的查询
    func cancelAndPrepare() {
        interrupt()
        isCancelled = false
    }

    // MARK: - 消息发送

    /// 发送问答请求（增强版）
    /// - Parameters:
    ///   - query: 用户问题
    ///   - imageBase64: 图片数据（可选）
    ///   - enableTTS: 是否启用 TTS
    ///   - voice: TTS 声音
    ///   - history: 对话历史
    ///   - completion: 完成回调（可选）
    func sendQuery(
        _ query: String,
        imageBase64: String? = nil,
        enableTTS: Bool = true,
        voice: String = "af_bella",
        history: [[String: String]]? = nil,
        completion: (() -> Void)? = nil
    ) {
        guard isConnected else {
            delegate?.webSocketDidReceiveError("WebSocket not connected")
            return
        }

        isCancelled = false
        pendingQuery = query
        contentBuffer = ""
        isWaitingForResponse = true
        completionHandler = completion

        startResponseTimer()

        var message: [String: Any] = [
            "type": "ask",
            "query": query,
            "enable_tts": enableTTS,
            "voice": voice
        ]

        if let image = imageBase64 {
            message["image"] = image
        }

        if let sessionId = currentSessionId {
            message["session_id"] = sessionId
        }

        if let history = history, !history.isEmpty {
            message["conversation_history"] = history
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: data, encoding: .utf8) {
                send(jsonString)
            }
        } catch {
            delegate?.webSocketDidReceiveError("Failed to encode message")
            isWaitingForResponse = false
            pendingQuery = nil
        }
    }

    /// 发送文本消息
    func sendMessage(_ text: String) {
        guard isConnected else {
            delegate?.webSocketDidReceiveError("WebSocket not connected")
            return
        }

        let message: [String: Any] = [
            "type": "message",
            "content": text,
            "session_id": currentSessionId ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: data, encoding: .utf8) {
            send(jsonString)
        }
    }

    /// 发送打断信号
    func sendInterrupt() {
        sendInterruptSignal()
    }

    /// 发送清空历史请求
    func sendClear() {
        guard isConnected else { return }

        let message: [String: Any] = [
            "type": "clear",
            "session_id": currentSessionId ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: data, encoding: .utf8) {
            send(jsonString)
        }
    }

    /// 发送获取历史请求
    func sendGetHistory() {
        guard isConnected else { return }

        let message: [String: Any] = [
            "type": "get_history",
            "session_id": currentSessionId ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: data, encoding: .utf8) {
            send(jsonString)
        }
    }

    /// 发送语音播报请求
    func sendSpeak(_ text: String, voice: String = "af_bella") {
        guard isConnected else { return }

        let message: [String: Any] = [
            "type": "speak",
            "text": text,
            "voice": voice,
            "session_id": currentSessionId ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: data, encoding: .utf8) {
            send(jsonString)
        }
    }

    /// 发送停止 TTS 请求
    func sendStopTTS() {
        guard isConnected else { return }

        let message: [String: Any] = [
            "type": "stop_tts",
            "session_id": currentSessionId ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: data, encoding: .utf8) {
            send(jsonString)
        }
    }

    /// 发送心跳
    func sendPing() {
        guard isConnected else { return }

        let pingMessage = #"{"type":"ping"}"#
        send(pingMessage)

        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("Ping failed: \(error)")
                self?.handlePingFailure()
            }
        }
    }

    private func send(_ message: String) {
        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        webSocketTask?.send(wsMessage) { [weak self] error in
            if let error = error {
                print("Send failed: \(error)")
                self?.delegate?.webSocketDidReceiveError("Failed to send message")
            }
        }
    }

    // MARK: - 消息接收

    private func receiveMessage() {
        guard !isCancelled else { return }

        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage()

            case .failure(let error):
                print("Receive failed: \(error)")
                if !(self?.isCancelled ?? true) {
                    self?.handleDisconnection(error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseMessage(text)

        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }

        @unknown default:
            break
        }
    }

    private func parseMessage(_ text: String) {
        responseTimer?.invalidate()
        responseTimer = nil

        guard let data = text.data(using: .utf8) else {
            if !isCancelled {
                contentBuffer += text
                delegate?.webSocketDidReceivePartial(self, content: text, isFirst: true)
            }
            return
        }

        do {
            let message = try JSONDecoder().decode(WSMessage.self, from: data)

            switch message.type {
            case "start", "thinking":
                print("WebSocket: Response started")
                contentBuffer = ""

            case "partial":
                if let content = message.content, !isCancelled {
                    contentBuffer += content
                    delegate?.webSocketDidReceivePartial(self, content: content, isFirst: false)
                }

            case "complete", "answer":
                handleResponseComplete(message.content)

            case "error":
                handleResponseError(message.content ?? "Unknown error")

            case "pong":
                print("WebSocket: Pong received")

            case "interrupted":
                handleServerInterrupt()

            case "tts_start":
                // TTS 开始处理
                print("WebSocket: TTS started")

            case "tts_ready":
                // TTS 完成，通知 delegate
                let dict: [String: Any] = [
                    "type": "tts_ready",
                    "audio_url": message.audioUrl ?? "",
                    "status": message.status ?? "ready"
                ]
                delegate?.webSocketDidReceiveMessage(dict)

            case "tts_error":
                let dict: [String: Any] = [
                    "type": "tts_error",
                    "error": message.error ?? "TTS error",
                    "status": "error"
                ]
                delegate?.webSocketDidReceiveMessage(dict)

            case "history_update":
                let dict: [String: Any] = [
                    "type": "history_update",
                    "history": message.history ?? [],
                    "total_count": message.totalCount ?? 0,
                    "history_length": message.historyLength ?? 0
                ]
                delegate?.webSocketDidReceiveMessage(dict)

            case "cleared":
                let dict: [String: Any] = [
                    "type": "cleared",
                    "status": "ok"
                ]
                delegate?.webSocketDidReceiveMessage(dict)

            default:
                // 对于其他类型的消息，转换为字典传给 delegate
                let dict: [String: Any] = [
                    "type": message.type,
                    "content": message.content ?? "",
                    "status": message.status ?? "",
                    "message": message.message ?? "",
                    "error": message.error ?? "",
                    "history_length": message.historyLength ?? 0,
                    "history": message.history ?? [],
                    "total_count": message.totalCount ?? 0,
                    "audio_url": message.audioUrl ?? "",
                    "vision_used": message.visionUsed ?? false,
                    "knowledge_points": message.knowledgePoints ?? [],
                    "suggested_followups": message.suggestedFollowups ?? []
                ]
                delegate?.webSocketDidReceiveMessage(dict)
            }

        } catch {
            // 如果不是标准 JSON，尝试直接作为文本处理
            if !isCancelled {
                contentBuffer += text
                delegate?.webSocketDidReceivePartial(self, content: text, isFirst: true)
            }
        }
    }

    // MARK: - 响应处理

    private func handleResponseComplete(_ content: String?) {
        guard !isCancelled else { return }

        isWaitingForResponse = false
        let finalContent = content ?? contentBuffer
        contentBuffer = ""

        completionHandler?()
        completionHandler = nil

        delegate?.webSocketDidReceiveComplete(self, content: finalContent, knowledgePoints: nil, suggestions: nil)

        pendingQuery = nil
    }

    private func handleResponseError(_ errorMessage: String) {
        isWaitingForResponse = false
        contentBuffer = ""

        completionHandler?()
        completionHandler = nil

        delegate?.webSocketDidReceiveError(errorMessage)
        pendingQuery = nil
    }

    private func handleServerInterrupt() {
        print("WebSocket: Server interrupted the request")
        isCancelled = true
        isWaitingForResponse = false
        contentBuffer = ""

        delegate?.webSocketDidReceiveError("Server interrupted the request")
        pendingQuery = nil
    }

    // MARK: - 连接状态

    private func sendConnectionMessage() {
        let message: [String: Any] = [
            "type": "connect",
            "client": "ios",
            "version": "1.0"
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: data, encoding: .utf8) {
                send(jsonString)
            }
        } catch {
            print("Failed to send connection message")
        }
    }

    private func handleDisconnection(error: Error?) {
        guard !isCancelled else { return }

        isConnected = false
        connectionState = .disconnected
        stopTimers()

        let disconnectError = error ?? WSClientError.disconnected
        delegate?.webSocketDidDisconnect(error: disconnectError)

        if isWaitingForResponse {
            attemptReconnect()
        }
    }

    // MARK: - 重连机制

    private func attemptReconnect() {
        guard !isCancelled,
              reconnectAttempts < maxReconnectAttempts,
              let sessionId = currentSessionId else {
            return
        }

        reconnectAttempts += 1
        connectionState = .reconnecting

        let delay = min(pow(2.0, Double(reconnectAttempts - 1)), 10.0)

        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.connect(sessionId: sessionId)
        }
    }

    // MARK: - 心跳保活

    private func startHeartbeat() {
        stopHeartbeat()

        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func handlePingFailure() {
        if isConnected {
            isConnected = false
            handleDisconnection(error: WSClientError.connectionFailed)
        }
    }

    // MARK: - 超时管理

    private func startConnectionTimeout() {
        responseTimer?.invalidate()
        responseTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            if self.connectionState == .connecting && !self.isConnected {
                self.delegate?.webSocketDidReceiveError("Connection timeout")
                self.disconnect()
            }
        }
    }

    private func startResponseTimer() {
        responseTimer?.invalidate()
        responseTimer = Timer.scheduledTimer(withTimeInterval: responseTimeout, repeats: false) { [weak self] _ in
            self?.handleResponseTimeout()
        }
    }

    private func handleResponseTimeout() {
        guard !isCancelled else { return }

        isWaitingForResponse = false
        delegate?.webSocketDidReceiveError("Response timeout")
        pendingQuery = nil

        attemptReconnect()
    }

    // MARK: - 定时器管理

    private func stopTimers() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        responseTimer?.invalidate()
        responseTimer = nil
    }

    // MARK: - 状态查询

    var isWebSocketConnected: Bool {
        return isConnected
    }

    var currentSession: String? {
        return currentSessionId
    }

    var isProcessing: Bool {
        return isWaitingForResponse && !isCancelled
    }

    var currentBuffer: String {
        return contentBuffer
    }

    // MARK: - 重新发送（用于重连后）

    /// 重新发送上一个查询
    func resendLastQuery() {
        guard let query = pendingQuery else { return }

        contentBuffer = ""
        isWaitingForResponse = true
        startResponseTimer()

        let message: [String: Any] = [
            "type": "ask",
            "query": query,
            "session_id": currentSessionId ?? ""
        ]

        if let data = try? JSONSerialization.data(withJSONObject: message),
           let jsonString = String(data: data, encoding: .utf8) {
            send(jsonString)
        }
    }

    deinit {
        cleanup()
    }
}

// MARK: - URLSessionWebSocketDelegate

extension QAWebSocketClient: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isConnected = true
        connectionState = .connected
        reconnectAttempts = 0
        stopTimers()
        delegate?.webSocketDidConnect()
        startHeartbeat()

        if let query = pendingQuery {
            sendQuery(query)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard !isCancelled else { return }

        isConnected = false
        connectionState = .disconnected
        stopTimers()

        if closeCode.rawValue == 1000 {
            delegate?.webSocketDidDisconnect(error: nil)
        } else {
            delegate?.webSocketDidDisconnect(error: WSClientError.disconnected)
        }

        if isWaitingForResponse {
            attemptReconnect()
        }
    }
}

// MARK: - 便捷初始化器

extension QAWebSocketClient {

    /// 创建并连接
    static func connect(sessionId: String, delegate: QAWebSocketClientDelegate?) -> QAWebSocketClient {
        let client = QAWebSocketClient()
        client.delegate = delegate
        client.connect(sessionId: sessionId)
        return client
    }
}

// MARK: - 扩展：中断请求详情

extension QAWebSocketClient {

    /// 获取当前连接状态描述
    var connectionStateDescription: String {
        switch connectionState {
        case .disconnected:
            return "已断开"
        case .connecting:
            return "连接中..."
        case .connected:
            return "已连接"
        case .reconnecting:
            return "重新连接中... (尝试 \(reconnectAttempts)/\(maxReconnectAttempts))"
        }
    }

    /// 检查是否应该重连
    var shouldAttemptReconnect: Bool {
        return !isCancelled && reconnectAttempts < maxReconnectAttempts && pendingQuery != nil
    }
}

// MARK: - 兼容旧 API

extension QAWebSocketClient {

    /// 发送问答请求（旧 API 兼容）
    func sendQuery(_ query: String, imageBase64: String?) {
        sendQuery(query, imageBase64: imageBase64, enableTTS: true, voice: "af_bella", history: nil, completion: nil)
    }

    /// 发送部分内容回调（兼容旧 delegate）
    func webSocketDidReceivePartial(content: String) {
        let dict: [String: Any] = [
            "type": "partial",
            "content": content
        ]
        delegate?.webSocketDidReceiveMessage(dict)
    }

    /// 发送完成内容回调（兼容旧 delegate）
    func webSocketDidReceiveComplete(content: String) {
        let dict: [String: Any] = [
            "type": "answer",
            "content": content
        ]
        delegate?.webSocketDidReceiveMessage(dict)
    }
}