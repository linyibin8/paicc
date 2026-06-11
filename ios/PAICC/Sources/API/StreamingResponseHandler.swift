import Foundation
import Combine

/// 流式响应处理结果
struct StreamingResult {
    var fullContent: String = ""
    var chunks: [String] = []
    var isComplete: Bool = false
    var error: Error?
}

/// 流式响应处理器 - 处理流式 API 响应
class StreamingResponseHandler: NSObject {

    // MARK: - 属性

    private var session: URLSession!
    private var currentTask: URLSessionDataTask?

    // 流式数据缓冲
    private var dataBuffer = Data()
    private var currentContent = ""
    private var chunks: [String] = []

    // 回调
    var onPartialContent: ((String) -> Void)?
    var onComplete: ((String) -> Void)?
    var onError: ((Error) -> Void)?
    var onProgress: ((Int, Int) -> Void)?  // (currentBytes, totalBytes)

    // 超时配置
    var timeout: TimeInterval = 60.0
    private var timeoutTimer: Timer?

    // MARK: - 初始化

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - 发起请求

    /// 发起流式请求
    /// - Parameters:
    ///   - request: QA 请求
    ///   - sessionId: 会话 ID（可选）
    func startStreaming(request: QARequest, sessionId: String? = nil) {
        cancel()

        guard let url = APIClient.shared.qaAskURL() else {
            onError?(APIError.invalidURL)
            return
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("chunked", forHTTPHeaderField: "Transfer-Encoding")

        let encoder = JSONEncoder()
        do {
            urlRequest.httpBody = try encoder.encode(request)
        } catch {
            onError?(APIError.decodingError)
            return
        }

        reset()
        startTimeoutTimer()
        currentTask = session.dataTask(with: urlRequest)
        currentTask?.resume()
    }

    /// 使用 POST 数据发起流式请求
    func startStreaming(postData: Data, endpoint: String) {
        cancel()

        guard let url = URL(string: endpoint) else {
            onError?(APIError.invalidURL)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        request.httpBody = postData

        reset()
        startTimeoutTimer()
        currentTask = session.dataTask(with: request)
        currentTask?.resume()
    }

    // MARK: - 数据处理

    private func reset() {
        dataBuffer = Data()
        currentContent = ""
        chunks = []
    }

    private func processReceivedData(_ data: Data) {
        dataBuffer.append(data)

        // 尝试解析 SSE 格式的数据
        // 格式: data: {"type": "partial", "content": "..."}\n\n
        guard let text = String(data: dataBuffer, encoding: .utf8) else {
            return
        }

        // 按行分割，处理 SSE 格式
        let lines = text.components(separatedBy: "\n")
        var processedText = ""

        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))

                // 尝试解析 JSON
                if let jsonData = jsonString.data(using: .utf8),
                   let message = try? JSONDecoder().decode(WSMessage.self, from: jsonData) {
                    switch message.type {
                    case .partial:
                        if let content = message.content {
                            currentContent += content
                            chunks.append(content)
                            onPartialContent?(currentContent)
                        }
                    case .complete:
                        if let content = message.content {
                            currentContent = content
                        }
                        onComplete?(currentContent)
                        cancel()
                        return
                    default:
                        break
                    }
                } else {
                    // 直接作为文本处理
                    processedText += jsonString
                }
            }
        }

        // 如果有纯文本内容
        if !processedText.isEmpty {
            currentContent += processedText
            chunks.append(processedText)
            onPartialContent?(currentContent)
        }
    }

    // MARK: - 超时管理

    private func startTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            self?.handleTimeout()
        }
    }

    private func handleTimeout() {
        let result = StreamingResult(
            fullContent: currentContent,
            chunks: chunks,
            isComplete: false,
            error: APIError.timeout
        )
        onError?(APIError.timeout)
        cancel()
    }

    // MARK: - 取消

    func cancel() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - 结果获取

    func getResult() -> StreamingResult {
        return StreamingResult(
            fullContent: currentContent,
            chunks: chunks,
            isComplete: true,
            error: nil
        )
    }

    deinit {
        cancel()
    }
}

// MARK: - URLSessionDataDelegate

extension StreamingResponseHandler: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        processReceivedData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        timeoutTimer?.invalidate()
        timeoutTimer = nil

        if let error = error {
            if (error as NSError).code == NSURLErrorCancelled {
                // 用户主动取消，不报告错误
                return
            }
            onError?(error)
        } else {
            // 请求完成但未收到 complete 消息
            if !currentContent.isEmpty {
                onComplete?(currentContent)
            }
        }
    }
}

// MARK: - 异步流式处理

extension StreamingResponseHandler {

    /// 异步等待流式响应完成
    func waitForCompletion() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var onCompleteHandler: ((String) -> Void)?
            var onErrorHandler: ((Error) -> Void)?

            onCompleteHandler = { [weak self] content in
                self?.onComplete = nil
                self?.onError = nil
                continuation.resume(returning: content)
            }

            onErrorHandler = { [weak self] error in
                self?.onComplete = nil
                self?.onError = nil
                continuation.resume(throwing: error)
            }

            self.onComplete = onCompleteHandler
            self.onError = onErrorHandler
        }
    }
}

// MARK: - Combine 支持

extension StreamingResponseHandler {

    /// 创建流式响应的 Publisher
    static func streamingPublisher(request: QARequest) -> AnyPublisher<String, Error> {
        let handler = StreamingResponseHandler()

        return Future<String, Error> { promise in
            handler.onPartialContent = { _ in }
            handler.onComplete = { content in
                promise(.success(content))
            }
            handler.onError = { error in
                promise(.failure(error))
            }

            handler.startStreaming(request: request)
        }
        .eraseToAnyPublisher()
    }
}