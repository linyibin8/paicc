import Foundation

/// API 客户端
class APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let baseURL: String

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)

        #if DEBUG
        baseURL = APIConfig.localBaseURL
        #else
        baseURL = APIConfig.baseURL
        #endif
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

    // MARK: - TTS

    func synthesize(text: String, voice: String = "af_heart") async throws -> Data {
        let endpoint = "\(baseURL)/tts/synthesize"

        let body: [String: String] = [
            "text": text,
            "voice": voice
        ]

        let data = try await post(endpoint, body: body)
        return data
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
}

// MARK: - 响应模型

struct CreateSessionResponse: Codable {
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

// MARK: - 错误

enum APIError: Error {
    case invalidURL
    case serverError
    case decodingError
    case networkError
}