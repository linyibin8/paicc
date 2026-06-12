import Speech
import AVFoundation

/// 语音服务 - 语音识别和 TTS
class VoiceService: NSObject {

    // MARK: - 单例
    static let shared = VoiceService()

    // MARK: - 属性
    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var isListening = false
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 3.0  // 3秒沉默自动结束

    // MARK: - TTS
    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - 回调
    var onSpeechResult: ((String) -> Void)?
    var onListeningStateChanged: ((Bool) -> Void)?

    // MARK: - 初始化

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
        super.init()
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Audio session setup error: \(error)")
        }
    }

    // MARK: - 语音识别

    func startListening() {
        guard !isListening else { return }

        // 请求权限
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.beginRecognition()
                case .denied, .restricted:
                    print("Speech recognition not authorized")
                case .notDetermined:
                    print("Speech recognition not determined")
                @unknown default:
                    break
                }
            }
        }
    }

    private func beginRecognition() {
        // 取消之前的任务
        recognitionTask?.cancel()
        recognitionTask = nil

        // 配置音频输入
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // 创建识别请求
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        if #available(iOS 16, *) {
            recognitionRequest?.addsPunctuation = true
        }

        // 开始识别
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            var isFinal = false

            if let result = result {
                let text = result.bestTranscription.formattedString
                isFinal = result.isFinal

                DispatchQueue.main.async {
                    self?.onSpeechResult?(text)
                }
            }

            if error != nil || isFinal {
                self?.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self?.recognitionRequest = nil
                self?.recognitionTask = nil
                self?.isListening = false

                DispatchQueue.main.async {
                    self?.onListeningStateChanged?(false)
                }
            }
        }

        // 启动音频引擎
        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
            onListeningStateChanged?(true)
            startSilenceTimer()
        } catch {
            print("Audio engine start error: \(error)")
        }
    }

    func stopListening() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        silenceTimer?.invalidate()
        silenceTimer = nil

        onListeningStateChanged?(false)
    }

    // MARK: - 沉默检测

    private func startSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            self?.stopListening()
        }
    }

    func resetSilenceTimer() {
        startSilenceTimer()
    }

    // MARK: - TTS 语音合成

    func speak(_ text: String, voice: String = "zh-CN") {
        // 停止之前的语音
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    func speakWithEndpoint(_ text: String, endpoint: String) async throws -> Data {
        // 从 TTS 服务获取音频
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "text": text,
            "voice": "zh-CN"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - 播放音频数据

    func playAudioData(_ data: Data) {
        do {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("tts_audio.wav")
            try data.write(to: tempURL)

            let player = try AVAudioPlayer(contentsOf: tempURL)
            player.play()
        } catch {
            print("Audio playback error: \(error)")
            // 回退到系统 TTS
            speak(String(data: data, encoding: .utf8) ?? "")
        }
    }
}