//
//  语音识别服务
//  使用 Speech Framework 实现本地 ASR
//

import Speech
import AVFoundation
import Combine

@MainActor
class SpeechService: ObservableObject {
    @Published var isListening: Bool = false
    @Published var recognizedText: String = ""
    @Published var isSpeaking: Bool = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let speechRecognizer: SFSpeechRecognizer!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // 静默检测
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 3.0  // 3秒静默自动结束

    // TTS 播放器
    private var audioPlayer: AVAudioPlayer?

    init() {
        // 初始化中文语音识别
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        setupAudioSession()
    }

    // MARK: - 权限申请

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                self?.authorizationStatus = status
            }
        }

        AVAudioApplication.requestRecordPermission { granted in
            print("Microphone permission: \(granted)")
        }
    }

    // MARK: - 音频会话

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
        } catch {
            print("Audio session setup error: \(error)")
        }
    }

    // MARK: - 语音识别

    func startListening() {
        guard authorizationStatus == .authorized else {
            requestPermission()
            return
        }

        isListening = true
        recognizedText = ""

        // 取消之前的任务
        recognitionTask?.cancel()
        recognitionTask = nil

        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldPartialFill = true
        recognitionRequest?.addsOnDeviceRecognition = true  // 本地识别

        let inputNode = audioEngine.inputNode

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.recognizedText = text

                    // 检查是否包含打断指令
                    if self.containsInterruptCommand(text) {
                        self.handleInterrupt()
                        return
                    }

                    // 检测静默
                    self.resetSilenceTimer()
                }

                if error != nil || result?.isFinal == true {
                    self.stopListening()
                }
            }
        }

        // 配置输入
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // 启动音频引擎
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("Audio engine start error: \(error)")
        }

        // 开始静默检测
        startSilenceTimer()
    }

    func stopListening() {
        isListening = false
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - 打断指令检测

    private func containsInterruptCommand(_ text: String) -> Bool {
        let commands = ["继续", "等等", "等一下", "停", "打断", "我还有问题", "再说一遍"]
        return commands.contains { text.contains($0) }
    }

    private func handleInterrupt() {
        stopListening()
        NotificationCenter.default.post(
            name: .speechInterruptCommand,
            object: recognizedText
        )
    }

    // MARK: - 静默检测

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopListening()
                if let text = self?.recognizedText, !text.isEmpty {
                    NotificationCenter.default.post(
                        name: .speechRecognitionComplete,
                        object: text
                    )
                }
            }
        }
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        startSilenceTimer()
    }

    // MARK: - TTS 播放

    func speak(_ text: String) {
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 1.0

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.speak(utterance)

        // 模拟播放完成
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(text.count) * 0.05) { [weak self] in
            self?.isSpeaking = false
        }
    }

    func stopSpeaking() {
        isSpeaking = false
        // 停止 AVSpeechSynthesizer
    }

    // MARK: - 播放思考音

    func playThinkingSound() {
        // 播放思考音（使用系统提示音或自定义音频）
        // 这里简化处理
        print("Playing thinking sound...")
    }

    func stopThinkingSound() {
        // 停止思考音
        print("Stop thinking sound")
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let speechInterruptCommand = Notification.Name("speechInterruptCommand")
    static let speechRecognitionComplete = Notification.Name("speechRecognitionComplete")
}