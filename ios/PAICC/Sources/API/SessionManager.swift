import Foundation

/// 会话状态
enum SessionState {
    case inactive
    case active(String)  // 包含 sessionId
    case expired
}

/// 会话管理器 - 管理学习会话的生命周期
class SessionManager {

    // MARK: - 单例
    static let shared = SessionManager()

    // MARK: - 属性

    private let apiClient = APIClient.shared
    private var currentSessionId: String?
    private var sessionStartTime: Date?
    private var sessionTimer: Timer?

    // 会话配置
    var sessionTimeout: TimeInterval = 30 * 60  // 30 分钟无活动超时
    var heartbeatInterval: TimeInterval = 5 * 60  // 5 分钟心跳

    // 回调
    var onSessionCreated: ((String) -> Void)?
    var onSessionEnded: (() -> Void)?
    var onSessionExpired: (() -> Void)?
    var onSessionError: ((Error) -> Void)?

    // MARK: - 状态

    private(set) var state: SessionState = .inactive

    var isActive: Bool {
        if case .active = state {
            return true
        }
        return false
    }

    var sessionId: String? {
        if case .active(let id) = state {
            return id
        }
        return nil
    }

    var sessionDuration: TimeInterval {
        guard let startTime = sessionStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    // MARK: - 初始化

    private init() {
        loadSavedSession()
    }

    // MARK: - 会话创建

    /// 创建新会话
    /// - Parameter studentGoal: 学生学习目标（可选）
    func createSession(studentGoal: String? = nil) async throws -> String {
        // 如果有现有会话，先结束
        if isActive {
            await endSession()
        }

        let sessionId = try await apiClient.createSession(studentGoal: studentGoal)

        currentSessionId = sessionId
        sessionStartTime = Date()
        state = .active(sessionId)

        // 保存会话
        saveSession()

        // 启动心跳
        startHeartbeat()

        // 通知回调
        onSessionCreated?(sessionId)

        return sessionId
    }

    /// 创建会话（使用回调）
    func createSession(studentGoal: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        Task {
            do {
                let sessionId = try await createSession(studentGoal: studentGoal)
                completion(.success(sessionId))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - 会话结束

    /// 结束当前会话
    func endSession() async {
        guard let sessionId = currentSessionId else { return }

        // 停止心跳
        stopHeartbeat()

        // 通知服务器
        do {
            try await apiClient.endSession(sessionId: sessionId)
        } catch {
            print("Failed to end session on server: \(error)")
        }

        // 清理本地状态
        clearSession()

        // 通知回调
        onSessionEnded?()
    }

    /// 结束会话（使用回调）
    func endSession(completion: @escaping () -> Void) {
        Task {
            await endSession()
            completion()
        }
    }

    // MARK: - 会话刷新

    /// 刷新会话（保持活跃）
    func refreshSession() async throws {
        guard let sessionId = currentSessionId else {
            throw SessionError.noActiveSession
        }

        // 重置会话开始时间
        sessionStartTime = Date()

        // 更新状态
        state = .active(sessionId)
        saveSession()
    }

    /// 延长会话超时
    func extendSession() {
        sessionStartTime = Date()
    }

    // MARK: - 会话验证

    /// 检查会话是否过期
    func checkSessionExpiry() -> Bool {
        guard let startTime = sessionStartTime else {
            return true
        }

        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed > sessionTimeout {
            handleSessionExpired()
            return true
        }
        return false
    }

    /// 强制刷新会话有效期
    func validateSession() {
        sessionStartTime = Date()
    }

    // MARK: - 心跳机制

    private func startHeartbeat() {
        stopHeartbeat()

        sessionTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            self?.performHeartbeat()
        }
    }

    private func stopHeartbeat() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    private func performHeartbeat() {
        // 检查会话是否过期
        if checkSessionExpiry() {
            return
        }

        // 发送心跳（如果后端支持）
        Task {
            // 可选：发送心跳到服务器
            // try? await apiClient.sendHeartbeat(sessionId: currentSessionId)
        }
    }

    // MARK: - 会话过期处理

    private func handleSessionExpired() {
        clearSession()
        state = .expired
        onSessionExpired?()
    }

    // MARK: - 持久化

    private func saveSession() {
        guard let sessionId = currentSessionId,
              let startTime = sessionStartTime else { return }

        UserDefaults.standard.set(sessionId, forKey: "current_session_id")
        UserDefaults.standard.set(startTime.timeIntervalSince1970, forKey: "session_start_time")
    }

    private func loadSavedSession() {
        guard let sessionId = UserDefaults.standard.string(forKey: "current_session_id"),
              let startTimeInterval = UserDefaults.standard.object(forKey: "session_start_time") as? TimeInterval else {
            return
        }

        let startTime = Date(timeIntervalSince1970: startTimeInterval)
        let elapsed = Date().timeIntervalSince(startTime)

        // 检查保存的会话是否过期
        if elapsed > sessionTimeout {
            clearSession()
        } else {
            currentSessionId = sessionId
            sessionStartTime = startTime
            state = .active(sessionId)
            startHeartbeat()
        }
    }

    private func clearSession() {
        currentSessionId = nil
        sessionStartTime = nil
        state = .inactive

        UserDefaults.standard.removeObject(forKey: "current_session_id")
        UserDefaults.standard.removeObject(forKey: "session_start_time")
    }

    // MARK: - 清理

    func forceEnd() async {
        stopHeartbeat()
        await endSession()
    }

    deinit {
        stopHeartbeat()
    }
}

// MARK: - 会话错误

enum SessionError: Error, LocalizedError {
    case noActiveSession
    case sessionExpired
    case creationFailed
    case networkError

    var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "没有活跃的会话"
        case .sessionExpired:
            return "会话已过期"
        case .creationFailed:
            return "会话创建失败"
        case .networkError:
            return "网络错误"
        }
    }
}

// MARK: - 会话信息

struct SessionInfo: Codable {
    let sessionId: String
    let startTime: Date
    let duration: TimeInterval
    let isActive: Bool
}

extension SessionManager {

    /// 获取当前会话信息
    func getCurrentSessionInfo() -> SessionInfo? {
        guard let sessionId = currentSessionId,
              let startTime = sessionStartTime else {
            return nil
        }

        return SessionInfo(
            sessionId: sessionId,
            startTime: startTime,
            duration: Date().timeIntervalSince(startTime),
            isActive: isActive
        )
    }
}