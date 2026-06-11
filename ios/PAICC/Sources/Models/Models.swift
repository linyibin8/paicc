import Foundation

/// API 配置
struct APIConfig {
    static let baseURL = "http://api.pai-cc.evowit.com/api/v1"
    static let ttsURL = "http://tts.pai-cc.evowit.com/api/v1"

    // 本地测试用
    #if DEBUG
    static let localBaseURL = "http://100.64.0.13:8090/api/v1"
    static let localTTSURL = "http://100.64.0.13:8090"
    static let wsBaseURL = "ws://100.64.0.13:8090/api/v1/qa/ws"
    #else
    static let localBaseURL = ""
    static let localTTSURL = ""
    static let wsBaseURL = "wss://api.pai-cc.evowit.com/api/v1/qa/ws"
    #endif
}

/// 学习会话
struct StudySession: Codable {
    let sessionId: String
    let studentId: String
    let status: String
    let studentGoal: String?
    let assistantFocus: String?
    let reportStyle: String
    let captureCount: Int
    let mistakeCount: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case studentId = "student_id"
        case status
        case studentGoal = "student_goal"
        case assistantFocus = "assistant_focus"
        case reportStyle = "report_style"
        case captureCount = "capture_count"
        case mistakeCount = "mistake_count"
        case createdAt = "created_at"
    }
}

/// 画面采集
struct Capture: Codable {
    let captureId: String
    let sessionId: String
    let sequence: Int
    let timestamp: String
    let qualityScore: Double
    let studentPresent: Bool
    let contentType: String?

    enum CodingKeys: String, CodingKey {
        case captureId = "capture_id"
        case sessionId = "session_id"
        case sequence
        case timestamp
        case qualityScore = "quality_score"
        case studentPresent = "student_present"
        case contentType = "content_type"
    }
}

/// 错题
struct Mistake: Codable, Identifiable {
    var id: String { mistakeId }
    let mistakeId: String
    let subject: String?
    let topic: String?
    let questionText: String
    let studentAnswer: String?
    let correctAnswer: String?
    let errorType: String?
    let difficulty: Double
    let status: String
    let reviewCount: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case mistakeId = "mistake_id"
        case subject
        case topic
        case questionText = "question_text"
        case studentAnswer = "student_answer"
        case correctAnswer = "correct_answer"
        case errorType = "error_type"
        case difficulty
        case status
        case reviewCount = "review_count"
        case createdAt = "created_at"
    }
}

/// AI 问答请求
struct QARequest: Codable {
    let query: String
    let imageBase64: String?
    let context: String?
    let sessionId: String?
    let studentGoal: String?

    enum CodingKeys: String, CodingKey {
        case query
        case imageBase64 = "image_base64"
        case context
        case sessionId = "session_id"
        case studentGoal = "student_goal"
    }
}

/// AI 问答响应
struct QAResponse: Codable {
    let answer: String
    let suggestions: [String]?
    let relatedMistakes: [String]?
    let knowledgePoints: [String]?

    enum CodingKeys: String, CodingKey {
        case answer
        case suggestions
        case relatedMistakes = "related_mistakes"
        case knowledgePoints = "knowledge_points"
    }
}

/// TTS 请求
struct TTSRequest: Codable {
    let text: String
    let voice: String
}

/// TTS 响应
struct TTSResponse: Codable {
    let audioUrl: String
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case audioUrl = "audio_url"
        case duration
    }
}

// MARK: - WebSocket 消息模型

/// WebSocket 消息类型
enum WSMessageType: String, Codable {
    case start = "start"
    case partial = "partial"
    case complete = "complete"
    case error = "error"
    case ping = "ping"
    case pong = "pong"
    case query = "query"
    case connect = "connect"
}

/// WebSocket 消息
struct WSMessage: Codable {
    let type: WSMessageType
    let content: String?
    let sessionId: String?
    let query: String?
    let imageBase64: String?
    let client: String?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case sessionId = "session_id"
        case query
        case imageBase64 = "image_base64"
        case client
        case version
    }
}

/// WebSocket 流式响应片段
struct StreamingChunk: Codable {
    let index: Int
    let content: String
    let isFinal: Bool

    enum CodingKeys: String, CodingKey {
        case index
        case content
        case isFinal = "is_final"
    }
}

// MARK: - TTS 下载模型

/// TTS 下载请求
struct TTSDownloadRequest: Codable {
    let text: String
    let voice: String
    let format: String

    enum CodingKeys: String, CodingKey {
        case text
        case voice
        case format
    }
}

/// TTS 下载响应
struct TTSDownloadResponse: Codable {
    let downloadUrl: String
    let duration: Double?
    let fileSize: Int?

    enum CodingKeys: String, CodingKey {
        case downloadUrl = "download_url"
        case duration
        case fileSize = "file_size"
    }
}