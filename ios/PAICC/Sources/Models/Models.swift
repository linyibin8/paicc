import Foundation

/// API 配置
struct APIConfig {
    static let baseURL = "http://api.pai-cc.evowit.com/api/v1"
    static let ttsURL = "http://tts.pai-cc.evowit.com/api/v1"

    // 本地测试用
    #if DEBUG
    static let localBaseURL = "http://100.64.0.13:8030/api/v1"
    static let localTTSURL = "http://100.64.0.13:8030"
    static let wsBaseURL = "ws://100.64.0.13:8030/api/v1/qa/ws"
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

/// WebSocket 消息类型（服务端返回的消息类型）
enum WSMessageType: String, Codable {
    case start = "start"
    case partial = "partial"
    case complete = "complete"
    case answer = "answer"
    case error = "error"
    case pong = "pong"
    case interrupt = "interrupt"
    case interrupted = "interrupted"
    case thinking = "thinking"
    case ttsStart = "tts_start"
    case ttsReady = "tts_ready"
    case ttsError = "tts_error"
    case historyUpdate = "history_update"
    case cleared = "cleared"
    case ping = "ping"
    case query = "query"
    case ask = "ask"
    case connect = "connect"
    case message = "message"
    case clear = "clear"
    case getHistory = "get_history"
    case speak = "speak"
    case stopTts = "stop_tts"
}

/// WebSocket 消息（与服务器通信的消息结构）
struct WSMessage: Codable {
    let type: String
    let content: String?
    let status: String?
    let message: String?
    let error: String?
    let historyLength: Int?
    let history: [[String: String]]?
    let totalCount: Int?
    let audioUrl: String?
    let visionUsed: Bool?
    let knowledgePoints: [String]?
    let suggestedFollowups: [String]?

    // 请求相关字段
    let query: String?
    let image: String?
    let imageBase64: String?
    let enableTts: Bool?
    let voice: String?
    let conversationHistory: [[String: String]]?
    let sessionId: String?
    let client: String?
    let version: String?
    let text: String?

    enum CodingKeys: String, CodingKey {
        case type, content, status, message, error
        case historyLength = "history_length"
        case history
        case totalCount = "total_count"
        case audioUrl = "audio_url"
        case visionUsed = "vision_used"
        case knowledgePoints = "knowledge_points"
        case suggestedFollowups = "suggested_followups"
        case query, image
        case imageBase64 = "image_base64"
        case enableTts = "enable_tts"
        case voice
        case conversationHistory = "conversation_history"
        case sessionId = "session_id"
        case client, version, text
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