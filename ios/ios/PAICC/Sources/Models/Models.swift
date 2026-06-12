import Foundation

/// API 配置
struct APIConfig {
    static let baseURL = "http://api.pai-cc.evowit.com/api/v1"
    static let ttsURL = "http://tts.pai-cc.evowit.com/api/v1"

    // 本地测试用
    #if DEBUG
    static let localBaseURL = "http://100.64.0.13:8027/api/v1"
    static let localTTSURL = "http://100.64.0.13:8880"
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