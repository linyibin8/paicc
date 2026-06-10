//
//  网络服务
//  处理与后端的通信
//

import Foundation
import Combine

@MainActor
class NetworkService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var lastError: String?

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?

    // 后端地址
    private let baseURL = "http://100.64.0.13:8029"
    private let wsURL = "ws://100.64.0.13:8029"

    enum NetworkError: Error {
        case connectionFailed
        case invalidResponse
        case serverError(String)
    }

    init() {
        checkConnection()
    }

    // MARK: - 连接检查

    func checkConnection() {
        Task {
            do {
                let url = URL(string: "\(baseURL)/health")!
                let (_, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse {
                    isConnected = httpResponse.statusCode == 200
                }
            } catch {
                isConnected = false
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - REST API

    func createSession(studentId: String?, goal: String?) async throws -> String {
        let url = URL(string: "\(baseURL)/api/v1/sessions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String?] = [
            "student_id": studentId,
            "student_goal": goal
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            let result = try JSONDecoder().decode(SessionCreateResponse.self, from: data)
            return result.session_id
        }

        throw NetworkError.invalidResponse
    }

    func uploadCapture(sessionId: String, image: Data, meta: CaptureMeta) async throws -> String {
        let url = URL(string: "\(baseURL)/api/v1/captures/upload")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 添加图片
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"capture.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(image)
        body.append("\r\n".data(using: .utf8)!)

        // 添加字段
        let fields: [String: Any] = [
            "session_id": sessionId,
            "timestamp": meta.timestamp,
            "sequence": meta.sequence,
            "quality_score": meta.qualityScore,
            "has_learning_material": meta.hasLearningMaterial,
            "has_hand_pen_person": meta.hasHandPenPerson,
            "student_present": meta.studentPresent,
            "material_type": meta.materialType,
            "change_type": meta.changeType,
            "is_key_frame": meta.isKeyFrame
        ]

        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            let result = try JSONDecoder().decode(CaptureUploadResponse.self, from: data)
            return result.capture_id
        }

        throw NetworkError.invalidResponse
    }

    func askQuestion(sessionId: String, image: Data, query: String, history: [[String: String]]) async throws -> QAResponse {
        let url = URL(string: "\(baseURL)/api/v1/qa/ask")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // 添加图片
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"question.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(image)
        body.append("\r\n".data(using: .utf8)!)

        // 添加字段
        let fields: [String: String] = [
            "session_id": sessionId,
            "query": query,
            "trigger_type": "voice",
            "conversation_history": try! JSONEncoder().encode(history).base64EncodedString()
        ]

        for (key, value) in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(QAResponse.self, from: data)
        }

        throw NetworkError.invalidResponse
    }

    // MARK: - WebSocket

    func connectWebSocket(sessionId: String) {
        let url = URL(string: "\(wsURL)/ws/qa/\(sessionId)")!
        webSocket = URLSession.shared.webSocketTask(with: url)
        webSocket?.resume()

        receiveMessage()
    }

    func disconnectWebSocket() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    func sendWebSocketMessage(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let string = String(data: data, encoding: .utf8) else { return }

        webSocket?.send(.string(string)) { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        }
    }

    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        Task { @MainActor in
                            self?.handleWebSocketMessage(json)
                        }
                    }
                default:
                    break
                }
                self?.receiveMessage()

            case .failure(let error):
                print("WebSocket receive error: \(error)")
            }
        }
    }

    private func handleWebSocketMessage(_ message: [String: Any]) {
        let type = message["type"] as? String ?? ""

        switch type {
        case "thinking":
            NotificationCenter.default.post(name: .aiThinking, object: nil)
        case "partial":
            let content = message["content"] as? String ?? ""
            NotificationCenter.default.post(name: .aiPartialAnswer, object: content)
        case "answer":
            let content = message["content"] as? String ?? ""
            NotificationCenter.default.post(name: .aiAnswerComplete, object: content)
        case "interrupted":
            NotificationCenter.default.post(name: .aiInterrupted, object: nil)
        default:
            break
        }
    }
}

// MARK: - Response Models

struct SessionCreateResponse: Codable {
    let session_id: String
}

struct CaptureUploadResponse: Codable {
    let capture_id: String
    let status: String
}

struct QAResponse: Codable {
    let answer: String
    let knowledge_points: [String]
    let suggested_followups: [String]
    let audio_url: String?
    let processing_time: Double
}

struct CaptureMeta {
    let timestamp: Int
    let sequence: Int
    let qualityScore: Double
    let hasLearningMaterial: Bool
    let hasHandPenPerson: Bool
    let studentPresent: Bool
    let materialType: String
    let changeType: String
    let isKeyFrame: Bool
}

// MARK: - Notification Names

extension Notification.Name {
    static let aiThinking = Notification.Name("aiThinking")
    static let aiPartialAnswer = Notification.Name("aiPartialAnswer")
    static let aiAnswerComplete = Notification.Name("aiAnswerComplete")
    static let aiInterrupted = Notification.Name("aiInterrupted")
}