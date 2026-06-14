import Foundation

/// API 客户端
class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: String
    private let wsBaseURL: String

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        #if DEBUG
        baseURL = APIConfig.localBaseURL
        wsBaseURL = APIConfig.wsBaseURL
        #else
        baseURL = APIConfig.baseURL
        wsBaseURL = APIConfig.wsBaseURL
        #endif
    }

    // MARK: - 服务器 URL

    /// 获取 WebSocket URL
    func webSocketURL(sessionId: String) -> URL? {
        return URL(string: "\(wsBaseURL)/\(sessionId)")
    }

    /// 获取 QA Ask URL
    func qaAskURL() -> URL? {
        return URL(string: "\(baseURL)/qa/ask")
    }

    /// 获取 TTS 合成 URL
    func ttsSynthesizeURL() -> URL? {
        return URL(string: "\(baseURL)/tts/synthesize")
    }

    // MARK: - 会话管理

    func createSession(studentGoal: String? = nil) async throws -> String {
        let endpoint = "\(baseURL)/sessions/"

        var body: [String: Any] = [
            "student_id": "default_student",
            "report_style": "normal"
        ]
        if let goal = studentGoal {
            body["student_goal"] = goal
        }

        let data = try await post(endpoint, body: body)
        let response = try JSONDecoder().decode(CreateSessionResponse.self, from: data)
        return response.sessionId
    }

    func endSession(sessionId: String) async throws {
        let endpoint = "\(baseURL)/sessions/\(sessionId)/end"
        _ = try await post(endpoint, body: [:])
    }

    // MARK: - 画面采集

    func uploadCapture(sessionId: String, imageData: Data, metadata: [String: Any]) async throws -> Capture {
        let endpoint = "\(baseURL)/captures/"
        let boundary = UUID().uuidString

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // 添加图片
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // 添加元数据
        if let metadataJson = try? JSONSerialization.data(withJSONObject: metadata) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"metadata\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/json\r\n\r\n".data(using: .utf8)!)
            body.append(metadataJson)
            body.append("\r\n".data(using: .utf8)!)
        }

        // 添加会话ID
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"session_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(sessionId)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(Capture.self, from: data)
    }

    // MARK: - AI 问答

    func askQuestion(_ request: QARequest) async throws -> QAResponse {
        let endpoint = "\(baseURL)/qa/ask"

        let encoder = JSONEncoder()
        let data = try await post(endpoint, body: encoder.encode(request))
        return try JSONDecoder().decode(QAResponse.self, from: data)
    }

    /// 构建 QA 请求体
    func buildQARequest(query: String, imageBase64: String? = nil, context: String? = nil, sessionId: String? = nil, studentGoal: String? = nil) -> QARequest {
        return QARequest(
            query: query,
            imageBase64: imageBase64,
            context: context,
            sessionId: sessionId,
            studentGoal: studentGoal
        )
    }

    // MARK: - TTS 语音合成

    /// 同步合成语音（返回音频数据）
    func synthesize(text: String, voice: String = "zh-CN") async throws -> Data {
        let endpoint = "\(baseURL)/tts/synthesize"

        let body: [String: Any] = [
            "text": text,
            "voice": voice
        ]

        let data = try await post(endpoint, body: body)
        return data
    }

    /// 异步合成语音（返回下载 URL）
    func synthesizeAsync(text: String, voice: String = "zh-CN", format: String = "mp3") async throws -> TTSDownloadResponse {
        let endpoint = "\(baseURL)/tts/synthesize"

        let body = TTSDownloadRequest(text: text, voice: voice, format: format)
        let encoder = JSONEncoder()
        let data = try await post(endpoint, body: encoder.encode(body))
        return try JSONDecoder().decode(TTSDownloadResponse.self, from: data)
    }

    /// 下载 TTS 音频文件
    func downloadTTSAudio(from urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        return data
    }

    /// 下载 TTS 音频并保存到本地
    func downloadAndSaveTTSAudio(text: String, voice: String = "zh-CN", filename: String? = nil) async throws -> URL {
        let response = try await synthesizeAsync(text: text, voice: voice)
        let audioData = try await downloadTTSAudio(from: response.downloadUrl)

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = filename ?? "tts_\(UUID().uuidString).mp3"
        let fileURL = documentsPath.appendingPathComponent(audioFilename)

        try audioData.write(to: fileURL)
        return fileURL
    }

    // MARK: - 错题

    func getMistakes(studentId: String? = nil, status: String? = nil) async throws -> [Mistake] {
        var endpoint = "\(baseURL)/mistakes"
        var queryItems: [String] = []

        if let sid = studentId {
            queryItems.append("student_id=\(sid)")
        }
        if let st = status {
            queryItems.append("status=\(st)")
        }

        if !queryItems.isEmpty {
            endpoint += "?" + queryItems.joined(separator: "&")
        }

        let data = try await get(endpoint)
        return try JSONDecoder().decode([Mistake].self, from: data)
    }

    // MARK: - 会话详情

    func getSession(sessionId: String) async throws -> SessionDetail {
        let data = try await get("\(baseURL)/sessions/\(sessionId)")
        return try JSONDecoder().decode(SessionDetail.self, from: data)
    }

    // MARK: - 错题管理

    func fetchMistakes(studentId: String) async throws -> [MistakeItem] {
        let data = try await get("\(baseURL)/mistakes?student_id=\(studentId)")
        return try JSONDecoder().decode([MistakeItem].self, from: data)
    }

    func updateMistake(mistakeId: String, status: String) async throws {
        let body: [String: Any] = ["status": status]
        _ = try await patch("\(baseURL)/mistakes/\(mistakeId)", body: body)
    }

    // MARK: - 复习队列

    func fetchReviewQueue(studentId: String) async throws -> ReviewQueueResponse {
        let data = try await get("\(baseURL)/review-queue/due?student_id=\(studentId)")
        return try JSONDecoder().decode(ReviewQueueResponse.self, from: data)
    }

    func submitReview(queueId: String, quality: Int) async throws -> ReviewResponse {
        let body: [String: Any] = ["quality": quality]
        let data = try await post("\(baseURL)/review-queue/\(queueId)/review", body: body)
        return try JSONDecoder().decode(ReviewResponse.self, from: data)
    }

    // MARK: - 学生画像

    func fetchStudentProfile(studentId: String) async throws -> StudentProfile {
        let data = try await get("\(baseURL)/student-profile/\(studentId)")
        return try JSONDecoder().decode(StudentProfile.self, from: data)
    }

    func fetchStudentStats(studentId: String) async throws -> StudentStats {
        let data = try await get("\(baseURL)/student-profile/\(studentId)/stats")
        return try JSONDecoder().decode(StudentStats.self, from: data)
    }

    // MARK: - 学习资产

    func fetchAssets(studentId: String, page: Int = 1, limit: Int = 20) async throws -> AssetsResponse {
        let data = try await get("\(baseURL)/assets?student_id=\(studentId)&page=\(page)&limit=\(limit)")
        return try JSONDecoder().decode(AssetsResponse.self, from: data)
    }

    // MARK: - TTS 语音合成

    func synthesizeSpeech(text: String) async throws -> URL {
        let body: [String: Any] = ["text": text]
        let data = try await post("\(baseURL)/tts/synthesize", body: body)

        struct TTSResponse: Codable {
            let audioUrl: String

            enum CodingKeys: String, CodingKey {
                case audioUrl = "audio_url"
            }
        }

        let response = try JSONDecoder().decode(TTSResponse.self, from: data)
        guard let url = URL(string: response.audioUrl) else {
            throw APIError.invalidURL
        }
        return url
    }

    // MARK: - 私有方法

    private func get(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        return data
    }

    private func post(_ urlString: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        return data
    }

    private func post(_ urlString: String, body: Data) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        return data
    }

    private func patch(_ urlString: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError
        }

        return data
    }
}

// MARK: - 响应模型

struct CreateSessionResponse: Codable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

struct SessionDetail: Codable {
    let sessionId: String
    let summary: String?
    let learningItems: [LearningItem]?
    let mistakeItems: [MistakeItem]?
    let startTime: String?
    let endTime: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case summary
        case learningItems = "learning_items"
        case mistakeItems = "mistake_items"
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

struct LearningItem: Codable {
    let id: String
    let content: String?
    let type: String?
}

// MARK: - API 扩展方法

// MARK: - 错误

enum APIError: Error, LocalizedError {
    case invalidURL
    case serverError
    case decodingError
    case networkError
    case noData
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "无效的 URL"
        case .serverError:
            return "服务器错误"
        case .decodingError:
            return "数据解析错误"
        case .networkError:
            return "网络错误"
        case .noData:
            return "无数据返回"
        case .timeout:
            return "请求超时"
        }
    }
}