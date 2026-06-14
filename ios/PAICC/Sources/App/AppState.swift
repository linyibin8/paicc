import Foundation
import Combine
import UIKit

class AppState {
    static let shared = AppState()

    // MARK: - Scan State
    enum ScanState: String {
        case idle
        case scanning
        case capturing
        case analyzing
        case qaActive
    }

    // MARK: - Published scan state
    @Published var scanState: ScanState = .idle

    // MARK: - Services
    var cameraService: CameraService!
    var qaService: QAService!

    // MARK: - Session State
    var currentSessionId: String? {
        get { lastSessionId }
        set { lastSessionId = newValue }
    }

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let studentId = "student_id"
        static let isLoggedIn = "is_logged_in"
        static let studentName = "student_name"
        static let lastSessionId = "last_session_id"
        static let serverHost = "server_host"
        static let serverPort = "server_port"
        static let autoTTS = "auto_tts"
        static let gestureEnabled = "gesture_enabled"
        static let thinkingSoundEnabled = "thinking_sound_enabled"
    }

    // MARK: - Server Configuration
    var serverHost: String {
        get { defaults.string(forKey: Keys.serverHost) ?? "paicc.evowit.com" }
        set { defaults.set(newValue, forKey: Keys.serverHost) }
    }

    var serverPort: Int {
        get { defaults.integer(forKey: Keys.serverPort) != 0 ? defaults.integer(forKey: Keys.serverPort) : 8030 }
        set { defaults.set(newValue, forKey: Keys.serverPort) }
    }

    var baseURL: String {
        return "http://\(serverHost):\(serverPort)"
    }

    // MARK: - User State
    var studentId: String {
        get {
            if let id = defaults.string(forKey: Keys.studentId), !id.isEmpty {
                return id
            }
            // 生成新的匿名 ID
            let newId = "student_\(UUID().uuidString.prefix(8))"
            defaults.set(newId, forKey: Keys.studentId)
            return newId
        }
        set { defaults.set(newValue, forKey: Keys.studentId) }
    }

    var studentName: String {
        get { defaults.string(forKey: Keys.studentName) ?? "" }
        set { defaults.set(newValue, forKey: Keys.studentName) }
    }

    var isLoggedIn: Bool {
        get { defaults.bool(forKey: Keys.isLoggedIn) }
        set { defaults.set(newValue, forKey: Keys.isLoggedIn) }
    }

    var lastSessionId: String? {
        get { defaults.string(forKey: Keys.lastSessionId) }
        set { defaults.set(newValue, forKey: Keys.lastSessionId) }
    }

    // MARK: - Settings
    var autoTTSEnabled: Bool {
        get { defaults.bool(forKey: Keys.autoTTS) }
        set { defaults.set(newValue, forKey: Keys.autoTTS) }
    }

    var gestureEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.gestureEnabled) == nil {
                return true // 默认开启
            }
            return defaults.bool(forKey: Keys.gestureEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.gestureEnabled) }
    }

    var thinkingSoundEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.thinkingSoundEnabled) == nil {
                return true // 默认开启
            }
            return defaults.bool(forKey: Keys.thinkingSoundEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.thinkingSoundEnabled) }
    }

    // MARK: - Initialization
    private init() {
        // 设置默认值
        if defaults.object(forKey: Keys.autoTTS) == nil {
            defaults.set(true, forKey: Keys.autoTTS)
        }
        if defaults.object(forKey: Keys.gestureEnabled) == nil {
            defaults.set(true, forKey: Keys.gestureEnabled)
        }
        if defaults.object(forKey: Keys.thinkingSoundEnabled) == nil {
            defaults.set(true, forKey: Keys.thinkingSoundEnabled)
        }
    }

    // MARK: - Login
    func login(name: String) {
        studentName = name
        isLoggedIn = true
    }

    func logout() {
        studentName = ""
        isLoggedIn = false
        lastSessionId = nil
    }

    // MARK: - Reset
    func resetAllSettings() {
        let domain = Bundle.main.bundleIdentifier!
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
    }

    // MARK: - Camera Setup
    func setupCamera(in view: UIView) {
        cameraService = CameraService()
        cameraService.setupCamera(in: view)
    }

    // MARK: - QA Setup
    func setupQA() {
        qaService = QAService()
    }

    // MARK: - Scanning Control
    func startScanning() {
        scanState = .scanning
        cameraService?.startCapture()
        cameraService?.enableGestureDetection()
    }

    func stopScanning() {
        scanState = .idle
        cameraService?.disableGestureDetection()
        cameraService?.stopCapture()
    }
}