import Foundation

/// WebSocket 连接状态
enum WSConnectionState {
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
        case .serverError(let message):
            return "服务器错误: \(message)"
        }
    }
}

/// WebSocket 客户端回调
protocol QAWebSocketClientDelegate: AnyObject {
    func webSocketDidConnect()
    func webSocketDidDisconnect(error: Error?)
    func webSocketDidReceivePartial(content: String)
    func webSocketDidReceiveComplete(content: String)
    func webSocketDidReceiveError(_ error: String)
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

    // 超时配置
    private var responseTimeout: TimeInterval = 60.0
    private var responseTimer: Timer?

    // 缓冲
    private var contentBuffer = ""
    private var isWaitingForResponse = false

    // MARK: - 初始化

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - 连接管理

    /// 连接到 WebSocket 服务器
    /// - Parameter sessionId: 会话 ID
    func connect(sessionId: String) {
        // 如果已连接，先断开
        if isConnected {
            disconnect()
        }

        currentSessionId = sessionId
        connectionState = .connecting

        // 使用 APIClient 获取 WebSocket URL
        guard let url = APIClient.shared.webSocketURL(sessionId: sessionId) else {
            delegate?.webSocketDidReceiveError("Invalid WebSocket URL")
            connectionState = .disconnected
            return
        }

        // 创建 WebSocket 连接
        webSocketTask = urlSession.webSocketTask(with: url)
        webSocketTask?.resume()

        // 开始接收消息
        receiveMessage()

        // 发送连接消息
        sendConnectionMessage()
    }

    /// 断开连接
    func disconnect() {
        stopTimers()

        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        connectionState = .disconnected
    }

    /// 断开并清理
    func cleanup() {
        disconnect()
        currentSessionId = nil
        contentBuffer = ""
        reconnectAttempts = 0
    }

    // MARK: - 消息发送

    /// 发送问答请求
    /// - Parameters:
    ///   - query: 用户问题
    ///   - imageBase64: 图片数据（可选）
    func sendQuery(_ query: String, imageBase64: String? = nil) {
        guard isConnected else {
            delegate?.webSocketDidReceiveError("WebSocket not connected")
            return
        }

        // 重置缓冲
        contentBuffer = ""
        isWaitingForResponse = true
        startResponseTimer()

        var message: [String: Any] = [
            "type": "query",
            "query": query
        ]

        if let image = imageBase64 {
            message["image_base64"] = image
        }

        if let sessionId = currentSessionId {
            message["session_id"] = sessionId
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: message)
            if let jsonString = String(data: data, encoding: .utf8) {
                send(jsonString)
            }
        } catch {
            delegate?.webSocketDidReceiveError("Failed to encode message")
            isWaitingForResponse = false
        }
    }

    /// 发送文本消息
    func sendMessage(_ text: String) {
        guard isConnected else {
            delegate?.webSocketDidReceiveError("WebSocket not connected")
            return
        }
        send(text)
    }

    /// 发送心跳
    func sendPing() {
        guard isConnected else { return }

        let pingMessage = #"{"type":"ping"}"#
        send(pingMessage)

        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                print("Ping failed: \(error)")
                self?.handleDisconnection(error: error)
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
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                // 继续接收下一条消息
                self?.receiveMessage()

            case .failure(let error):
                print("Receive failed: \(error)")
                self?.handleDisconnection(error: error)
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
        // 停止响应计时器
        responseTimer?.invalidate()
        responseTimer = nil

        // 尝试解析 JSON
        guard let data = text.data(using: .utf8) else {
            // 无法解析，直接作为文本处理
            delegate?.webSocketDidReceivePartial(text)
            return
        }

        do {
            let message = try JSONDecoder().decode(WSMessage.self, from: data)

            switch message.type {
            case .start:
                // 开始接收响应
                print("WebSocket: Response started")
                contentBuffer = ""

            case .partial:
                // 流式响应片段
                if let content = message.content {
                    contentBuffer += content
                    delegate?.webSocketDidReceivePartial(content)
                }

            case .complete:
                // 响应完成
                isWaitingForResponse = false
                let finalContent = message.content ?? contentBuffer
                contentBuffer = ""
                delegate?.webSocketDidReceiveComplete(finalContent)

            case .error:
                // 错误
                isWaitingForResponse = false
                delegate?.webSocketDidReceiveError(message.content ?? "Unknown error")

            case .pong:
                // 心跳响应
                print("WebSocket: Pong received")

            default:
                break
            }

        } catch {
            // 如果不是标准 JSON，尝试直接作为文本处理
            contentBuffer += text
            delegate?.webSocketDidReceivePartial(text)
        }
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
        isConnected = false
        connectionState = .disconnected
        stopTimers()
        delegate?.webSocketDidDisconnect(error: error)

        // 尝试重连
        attemptReconnect()
    }

    // MARK: - 重连机制

    private func attemptReconnect() {
        guard reconnectAttempts < maxReconnectAttempts,
              let sessionId = currentSessionId else {
            return
        }

        reconnectAttempts += 1
        connectionState = .reconnecting

        // 延迟重连（指数退避）
        let delay = pow(2.0, Double(reconnectAttempts - 1))

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

    // MARK: - 响应超时

    private func startResponseTimer() {
        responseTimer?.invalidate()
        responseTimer = Timer.scheduledTimer(withTimeInterval: responseTimeout, repeats: false) { [weak self] _ in
            self?.handleResponseTimeout()
        }
    }

    private func handleResponseTimeout() {
        isWaitingForResponse = false
        delegate?.webSocketDidReceiveError("Response timeout")
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
        delegate?.webSocketDidConnect()
        startHeartbeat()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        isConnected = false
        connectionState = .disconnected
        delegate?.webSocketDidDisconnect(error: nil)
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